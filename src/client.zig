const std = @import("std");

const root = @import("root.zig");
const c = @import("cgrpc");
const t = @import("types.zig");
const makeSlice = @import("slice.zig").makeSlice;
const asZigSlice = @import("slice.zig").asZigSlice;

const Allocator = std.mem.Allocator;
const Deadline = root.Deadline;
const PluckQueue = root.PluckQueue;
const Channel = root.Channel;
const errors = root.errors;

pub const Batch = struct {
    outbound: ?*t.ByteBuffer = null,
    inbound: ?*t.ByteBuffer = null,
    is_inbound_expected: bool = false,
    status: Status = .{},
    metadata: std.ArrayList(t.Metadata),
    allocator: Allocator,

    /// Possible failures from incorrect API usage; indicate a bug in the caller.
    pub const Error = errors.UsageError;

    pub fn init(gpa: Allocator) Batch {
        return .{ .allocator = gpa, .metadata = .empty };
    }

    /// Errors that may occur when reading back a received message.
    pub const RecvError = error{
        /// expectReceivedMessage was not called before this batch completed.
        NoInboundMessageExpected,
        OutOfMemory,
    };

    /// Errors that may occur while waiting for a batch to complete.
    pub const WaitError = RecvError || error{
        /// The completion queue was shut down before this batch's event was received.
        QueueShutdown,
    };

    pub fn addMetadata(self: *Batch, key: []const u8, value: []const u8) error{OutOfMemory}!void {
        const k: t.Slice = try makeSlice(self.allocator, key);
        errdefer c.grpc_slice_unref(k);
        const v: t.Slice = try makeSlice(self.allocator, value);
        errdefer c.grpc_slice_unref(v);

        try self.metadata.append(self.allocator, .{ .key = k, .value = v });
    }

    pub fn setMessageToSend(self: *Batch, message: []const u8) error{OutOfMemory}!void {
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

    /// A non-OK status code received from the server.
    pub const Failure = struct {
        code: c.grpc_status_code,
        /// When coming from `Batch.wait`: points into gRPC-owned memory, valid until `deinit`.
        /// When coming from `rawUnaryCall`: allocated with the provided allocator, caller must free.
        details: []const u8,

        pub fn toZigError(self: Failure) errors.StatusError {
            return switch (self.code) {
                c.GRPC_STATUS_CANCELLED => error.Cancelled,
                c.GRPC_STATUS_UNKNOWN => error.Unknown,
                c.GRPC_STATUS_INVALID_ARGUMENT => error.InvalidArgument,
                c.GRPC_STATUS_DEADLINE_EXCEEDED => error.DeadlineExceeded,
                c.GRPC_STATUS_NOT_FOUND => error.NotFound,
                c.GRPC_STATUS_ALREADY_EXISTS => error.AlreadyExists,
                c.GRPC_STATUS_PERMISSION_DENIED => error.PermissionDenied,
                c.GRPC_STATUS_RESOURCE_EXHAUSTED => error.ResourceExhausted,
                c.GRPC_STATUS_FAILED_PRECONDITION => error.FailedPrecondition,
                c.GRPC_STATUS_ABORTED => error.Aborted,
                c.GRPC_STATUS_OUT_OF_RANGE => error.OutOfRange,
                c.GRPC_STATUS_UNIMPLEMENTED => error.Unimplemented,
                c.GRPC_STATUS_INTERNAL => error.Internal,
                c.GRPC_STATUS_UNAVAILABLE => error.Unavailable,
                c.GRPC_STATUS_DATA_LOSS => error.DataLoss,
                c.GRPC_STATUS_UNAUTHENTICATED => error.Unauthenticated,
                else => error.GrpcError,
            };
        }
    };

    pub const Result = union(enum) {
        timeout,
        /// The batch operation failed (event.success == 0). Status fields are not populated.
        operation_failed,
        /// A non-OK status code was received. `details` points into gRPC-owned memory, valid until `deinit`.
        failure: Failure,
        /// The call succeeded. `message` is allocated and must be freed by the caller.
        /// Null if `expectReceivedMessage` was not called on this batch.
        success: ?[]u8,
    };

    pub fn start(self: *Batch, call: *t.Call) (Error || error{OutOfMemory})!void {
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
            c.GRPC_CALL_ERROR_NOT_ON_SERVER => Error.NotOnServer,
            c.GRPC_CALL_ERROR_NOT_ON_CLIENT => Error.NotOnClient,
            c.GRPC_CALL_ERROR_ALREADY_ACCEPTED => Error.AlreadyAccepted,
            c.GRPC_CALL_ERROR_ALREADY_INVOKED => Error.AlreadyInvoked,
            c.GRPC_CALL_ERROR_NOT_INVOKED => Error.NotInvoked,
            c.GRPC_CALL_ERROR_ALREADY_FINISHED => Error.AlreadyFinished,
            c.GRPC_CALL_ERROR_TOO_MANY_OPERATIONS => Error.TooManyOperations,
            c.GRPC_CALL_ERROR_INVALID_FLAGS => Error.InvalidFlags,
            c.GRPC_CALL_ERROR_INVALID_METADATA => Error.InvalidMetadata,
            c.GRPC_CALL_ERROR_INVALID_MESSAGE => Error.InvalidMessage,
            c.GRPC_CALL_ERROR_NOT_SERVER_COMPLETION_QUEUE => Error.NotServerCompletionQueue,
            c.GRPC_CALL_ERROR_BATCH_TOO_BIG => Error.BatchTooBig,
            c.GRPC_CALL_ERROR_PAYLOAD_TYPE_MISMATCH => Error.PayloadTypeMismatch,
            c.GRPC_CALL_ERROR_COMPLETION_QUEUE_SHUTDOWN => Error.CompletionQueueShutdown,
            else => Error.Unknown, // GRPC_CALL_ERROR
        };
    }

    /// To be called only after the completion queue event confirmed this batch succeeded.
    ///
    /// Returned slice must be freed by the caller.
    /// An error is returned if no inbound message is expected.
    /// null is returned if no message was received.
    pub fn getReceivedMessage(self: *Batch) RecvError!?[]u8 {
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
    pub fn wait(self: *Batch, queue: *PluckQueue, deadline: Deadline) WaitError!Result {
        const event = queue.pluck(@ptrCast(self), deadline) orelse return error.QueueShutdown;
        return switch (event) {
            .timeout => .timeout,
            .failure => .operation_failed,
            .success => if (self.status.code != c.GRPC_STATUS_OK)
                .{ .failure = .{
                    .code = self.status.code,
                    .details = asZigSlice(self.status.details),
                } }
            else
                .{ .success = if (self.is_inbound_expected)
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

/// Possible failures of a rawUnaryCall that are not gRPC-level errors.
pub const RawCallError = Batch.Error || Batch.WaitError;

/// Perform a raw unary gRPC call with pre-encoded protobuf request bytes.
///
/// Handles the full call lifecycle (create, start, wait, destroy).
/// Returns a `Batch.Result`. In the `.failure` case, `details` is allocated with `allocator`
/// and must be freed by the caller (unlike `Batch.Result` from `Batch.wait`, where it is gRPC-owned).
pub fn rawUnaryCall(
    allocator: Allocator,
    channel: *Channel,
    queue: *PluckQueue,
    path: []const u8,
    data: []const u8,
    deadline: Deadline,
) RawCallError!Batch.Result {
    const call = channel.createCall(queue, path, deadline);
    defer c.grpc_call_unref(call);

    var batch: Batch = .init(allocator);
    defer batch.deinit();
    try batch.setMessageToSend(data);
    batch.expectReceivedMessage();
    try batch.start(call);

    return switch (try batch.wait(queue, deadline)) {
        .timeout => .timeout,
        .operation_failed => .operation_failed,
        .failure => |f| .{
            .failure = .{
                .code = f.code,
                // Dupe details: f.details points into gRPC-owned memory freed by batch.deinit().
                .details = try allocator.dupe(u8, f.details),
            },
        },
        .success => |bytes| .{ .success = bytes },
    };
}
