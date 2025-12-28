const std = @import("std");

const root = @import("root.zig");
const c = @import("cgrpc");
const t = @import("types.zig");
const make_slice = @import("slice.zig").make_slice;

const Allocator = std.mem.Allocator;
const Deadline = root.Deadline;

pub const Batch = struct {
    outbound: std.ArrayList(*t.ByteBuffer),
    inbound: std.ArrayList(?*t.ByteBuffer),
    operations: std.ArrayList(t.Operation),
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

    pub fn init(gpa: Allocator) !Batch {
        // inbound is preallocated and cannot grow as pointers are passed
        // to gRPC but are invalidated when growing the list
        return .{
            .outbound = .empty,
            .inbound = try .initCapacity(gpa, 16),
            .operations = .empty,
            .allocator = gpa,
            .metadata = .empty,
        };
    }

    pub fn addMetadata(self: *Batch, key: []const u8, value: []const u8) !void {
        const k: t.Slice = try make_slice(self.allocator, key);
        errdefer c.grpc_slice_unref(k);
        const v: t.Slice = try make_slice(self.allocator, value);
        errdefer c.grpc_slice_unref(v);

        try self.metadata.append(self.allocator, .{ .key = k, .value = v });
    }

    pub fn addMessageToSend(self: *Batch, message: []const u8) !void {
        var slice: t.Slice = try make_slice(self.allocator, message);
        defer c.grpc_slice_unref(slice);

        const byte_buffer: *t.ByteBuffer = c.grpc_raw_byte_buffer_create((&slice)[0..1], 1);
        errdefer c.grpc_byte_buffer_destroy(byte_buffer);
        try self.outbound.append(self.allocator, byte_buffer);

        const op: t.Operation = .{
            .op = c.GRPC_OP_SEND_MESSAGE,
            .data = .{ .send_message = .{ .send_message = self.outbound.getLast() } },
        };
        try self.operations.append(self.allocator, op);
    }

    pub fn expectReceivedMessage(self: *Batch) !void {
        const dest: *?*t.ByteBuffer = try self.inbound.addOneBounded();
        dest.* = null;
        const op: t.Operation = .{
            .op = c.GRPC_OP_RECV_MESSAGE,
            .data = .{ .recv_message = .{ .recv_message = @ptrCast(dest) } },
        };
        try self.operations.append(self.allocator, op);
    }

    pub const Status = struct {
        description: ?[*:0]u8 = null,
        status: c.grpc_status_code = c.GRPC_STATUS_OK,
        details: t.Slice = .{},
        leading_metadata: c.grpc_metadata_array = .{},
        trailing_metadata: c.grpc_metadata_array = .{},
    };

    pub fn start(self: *Batch, call: *t.Call, tag: *opaque {}, status: *Status) !void {
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
                .recv_initial_metadata = &status.leading_metadata,
            } },
        };
        const penultimate: t.Operation = .{
            .op = c.GRPC_OP_SEND_CLOSE_FROM_CLIENT,
        };
        const last: t.Operation = .{
            .op = c.GRPC_OP_RECV_STATUS_ON_CLIENT,
            .data = .{ .recv_status_on_client = .{
                .error_string = @ptrCast(&status.description),
                .status = &status.status,
                .status_details = &status.details,
                .trailing_metadata = &status.trailing_metadata,
            } },
        };
        try self.operations.insertSlice(self.allocator, 0, &.{ first, second });
        try self.operations.appendSlice(self.allocator, &.{ penultimate, last });

        return switch (c.grpc_call_start_batch(
            call,
            self.operations.items.ptr,
            self.operations.items.len,
            @ptrCast(tag),
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

    /// To be called only after the completion queue event confirmed this batch succeeded
    ///
    /// Returned slice must be freed
    pub fn nextReceivedMessage(self: *Batch) !?[]u8 {
        const buffer = (self.inbound.pop() orelse return null) orelse return error.NotReceived;
        var reader: c.grpc_byte_buffer_reader = undefined;
        if (c.grpc_byte_buffer_reader_init(&reader, buffer) != 1) unreachable;
        defer c.grpc_byte_buffer_reader_destroy(&reader); // useless

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

    /// Destroy all gRPC buffers and release allocated memory
    pub fn deinit(self: *Batch) void {
        for (self.outbound.items) |buffer| {
            c.grpc_byte_buffer_destroy(buffer);
        }
        self.outbound.deinit(self.allocator);
        for (self.inbound.items) |buffer| {
            if (buffer) |buf|
                c.grpc_byte_buffer_destroy(buf);
        }
        self.inbound.deinit(self.allocator);
        self.operations.deinit(self.allocator);
        for (self.metadata.items) |metadata| {
            c.grpc_slice_unref(metadata.key);
            c.grpc_slice_unref(metadata.value);
        }
        self.metadata.deinit(self.allocator);
    }
};
