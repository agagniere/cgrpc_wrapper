const std = @import("std");

const root = @import("root.zig");
const c = @import("cgrpc");
const t = @import("types.zig");
const makeSlice = @import("slice.zig").makeSlice;
const asZigSlice = @import("slice.zig").asZigSlice;

const Allocator = std.mem.Allocator;
const Deadline = root.Deadline;
const PluckQueue = root.PluckQueue;

pub const Batch = struct {
    outbound: ?*t.ByteBuffer = null,
    inbound: ?*t.ByteBuffer = null,
    is_inbound_expected: bool = false,
    status: Status = .{},
    metadata: std.ArrayList(t.Metadata),
    allocator: Allocator,

    /// Possible failures of a grpc call.
    /// Receiving any value listed here is an indication of a bug in the caller.
    pub const Error = error{
        /// Something failed, we don't know what
        unknown,
        /// This method is not available on the server
        not_on_server,
        /// This method is not available on the client
        not_on_client,
        /// This method must be called before server_accept
        already_accepted,
        /// this method must be called before invoke
        already_invoked,
        /// This method must be called after invoke
        not_invoked,
        /// This call is already finished (writes_done or write_status has already been called)
        already_finished,
        /// There is already an outstanding read/write operation on the call
        too_many_operations,
        /// The flags value was illegal for this call
        invalid_flags,
        /// Invalid metadata was passed to this call
        invalid_metadata,
        /// Invalid message was passed to this call
        invalid_message,
        /// Completion queue for notification has not been registered with the server
        not_server_completion_queue,
        /// This batch of operations leads to more operations than allowed
        batch_too_big,
        /// Payload type requested is not the type registered
        payload_type_mismatch,
        /// Completion queue has been shutdown
        completion_queue_shutdown,
    };

    pub fn init(gpa: Allocator) Batch {
        return .{ .allocator = gpa, .metadata = .empty };
    }

    pub fn addMetadata(self: *Batch, key: []const u8, value: []const u8) !void {
        const k: t.Slice = try makeSlice(self.allocator, key);
        errdefer c.grpc_slice_unref(k);
        const v: t.Slice = try makeSlice(self.allocator, value);
        errdefer c.grpc_slice_unref(v);

        try self.metadata.append(self.allocator, .{ .key = k, .value = v });
    }

    pub fn setMessageToSend(self: *Batch, message: []const u8) !void {
        var slice: t.Slice = try makeSlice(self.allocator, message);
        defer c.grpc_slice_unref(slice);
        self.outbound = c.grpc_raw_byte_buffer_create((&slice)[0..1], 1);
    }

    pub fn expectReceivedMessage(self: *Batch) void {
        self.is_inbound_expected = true;
    }

    pub const Status = struct {
        description: ?[*:0]u8 = null,
        code: c.grpc_status_code = c.GRPC_STATUS_OK,
        details: t.Slice = .{},
        leading_metadata: c.grpc_metadata_array = .{},
        trailing_metadata: c.grpc_metadata_array = .{},
    };

    pub const Result = union(enum) {
        timeout,
        /// The call failed. `details` points into gRPC-owned memory, valid until `deinit`.
        failure: struct { code: c.grpc_status_code, details: []const u8 },
        /// The call succeeded. `message` is allocated and must be freed by the caller.
        /// Null if `expectReceivedMessage` was not called on this batch.
        success: ?[]u8,
    };

    pub fn start(self: *Batch, call: *t.Call) !void {
        var operations = try std.ArrayList(t.Operation).initCapacity(self.allocator, 6);
        defer operations.deinit(self.allocator);

        const first: t.Operation = .{
            .op = c.GRPC_OP_SEND_INITIAL_METADATA,
            .data = .{ .send_initial_metadata = .{
                .count = self.metadata.items.len,
                .metadata = self.metadata.items.ptr,
                .maybe_compression_level = .{
                    .is_set = 0,
                    .level = c.GRPC_COMPRESS_LEVEL_NONE,
                },
            } },
        };
        const second: t.Operation = .{
            .op = c.GRPC_OP_RECV_INITIAL_METADATA,
            .data = .{ .recv_initial_metadata = .{
                .recv_initial_metadata = &self.status.leading_metadata,
            } },
        };
        const penultimate: t.Operation = .{
            .op = c.GRPC_OP_SEND_CLOSE_FROM_CLIENT,
        };
        const last: t.Operation = .{
            .op = c.GRPC_OP_RECV_STATUS_ON_CLIENT,
            .data = .{ .recv_status_on_client = .{
                .error_string = @ptrCast(&self.status.description),
                .status = &self.status.code,
                .status_details = &self.status.details,
                .trailing_metadata = &self.status.trailing_metadata,
            } },
        };
        try operations.appendSlice(self.allocator, &.{ first, second });
        if (self.outbound) |buf| try operations.append(self.allocator, .{
            .op = c.GRPC_OP_SEND_MESSAGE,
            .data = .{ .send_message = .{ .send_message = buf } },
        });
        if (self.is_inbound_expected) try operations.append(self.allocator, .{
            .op = c.GRPC_OP_RECV_MESSAGE,
            .data = .{ .recv_message = .{ .recv_message = @ptrCast(&self.inbound) } },
        });
        try operations.appendSlice(self.allocator, &.{ penultimate, last });

        return switch (c.grpc_call_start_batch(
            call,
            operations.items.ptr,
            operations.items.len,
            @ptrCast(self),
            null,
        )) {
            c.GRPC_CALL_OK => {},
            c.GRPC_CALL_ERROR_NOT_ON_SERVER => Error.not_on_server,
            c.GRPC_CALL_ERROR_NOT_ON_CLIENT => Error.not_on_client,
            c.GRPC_CALL_ERROR_ALREADY_ACCEPTED => Error.already_accepted,
            c.GRPC_CALL_ERROR_ALREADY_INVOKED => Error.already_invoked,
            c.GRPC_CALL_ERROR_NOT_INVOKED => Error.not_invoked,
            c.GRPC_CALL_ERROR_ALREADY_FINISHED => Error.already_finished,
            c.GRPC_CALL_ERROR_TOO_MANY_OPERATIONS => Error.too_many_operations,
            c.GRPC_CALL_ERROR_INVALID_FLAGS => Error.invalid_flags,
            c.GRPC_CALL_ERROR_INVALID_METADATA => Error.invalid_metadata,
            c.GRPC_CALL_ERROR_INVALID_MESSAGE => Error.invalid_message,
            c.GRPC_CALL_ERROR_NOT_SERVER_COMPLETION_QUEUE => Error.not_server_completion_queue,
            c.GRPC_CALL_ERROR_BATCH_TOO_BIG => Error.batch_too_big,
            c.GRPC_CALL_ERROR_PAYLOAD_TYPE_MISMATCH => Error.payload_type_mismatch,
            c.GRPC_CALL_ERROR_COMPLETION_QUEUE_SHUTDOWN => Error.completion_queue_shutdown,
            else => Error.unknown, // GRPC_CALL_ERROR
        };
    }

    /// To be called only after the completion queue event confirmed this batch succeeded.
    ///
    /// Returned slice must be freed by the caller.
    /// An error is returned if no inbound message is expected.
    /// null is returned if no message was received.
    pub fn getReceivedMessage(self: *Batch) !?[]u8 {
        if (!self.is_inbound_expected) return error.NoInboundMessageExpected;
        const buffer = self.inbound orelse return null;
        var reader: c.grpc_byte_buffer_reader = undefined;
        if (c.grpc_byte_buffer_reader_init(&reader, buffer) != 1) unreachable;
        defer c.grpc_byte_buffer_reader_destroy(&reader); // this is a noop

        const length = c.grpc_byte_buffer_length(buffer);
        const result = try self.allocator.alloc(u8, length);
        var written: usize = 0;

        var slice: t.Slice = undefined;
        while (c.grpc_byte_buffer_reader_next(&reader, &slice) == 1) {
            defer c.grpc_slice_unref(slice);
            const size = if (slice.refcount == null) slice.data.inlined.length else slice.data.refcounted.length;
            if (slice.refcount == null) {
                @memcpy(result[written..][0..size], slice.data.inlined.bytes[0..size]);
            } else {
                @memcpy(result[written..][0..size], slice.data.refcounted.bytes[0..size]);
            }
            written += size;
        }
        return result;
    }

    /// Wait for this batch's completion event, then return the result.
    pub fn wait(self: *Batch, queue: *PluckQueue, deadline: Deadline) !Result {
        const event = queue.pluck(@ptrCast(self), deadline) orelse return error.QueueShutdown;
        return switch (event) {
            .timeout => .timeout,
            .failure => .{ .failure = .{
                .code = self.status.code,
                .details = asZigSlice(self.status.details),
            } },
            .success => .{ .success = if (self.is_inbound_expected)
                try self.getReceivedMessage()
            else
                null },
        };
    }

    /// Destroy all gRPC buffers and release allocated memory
    pub fn deinit(self: *Batch) void {
        if (self.outbound) |buf| c.grpc_byte_buffer_destroy(buf);
        if (self.inbound) |buf| c.grpc_byte_buffer_destroy(buf);
        for (self.metadata.items) |metadata| {
            c.grpc_slice_unref(metadata.key);
            c.grpc_slice_unref(metadata.value);
        }
        self.metadata.deinit(self.allocator);
    }
};
