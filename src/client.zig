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

pub const Credentials = @import("credentials.zig").ChannelCredentials;

/// A metadata element to send with a call.
/// gRPC only accepts keys made of lowercase letters, digits, `-`, `_` and `.`,
/// and values of printable ASCII, unless the key ends with `-bin`.
pub const Metadata = struct {
    key: []const u8,
    value: []const u8,
};

pub const CallOptions = struct {
    deadline: Deadline,
    metadata: []const Metadata = &.{},
};

pub const Batch = struct {
    outbound: ?*t.ByteBuffer = null,
    inbound: ?*t.ByteBuffer = null,
    is_inbound_expected: bool = false,
    status: Status = .{},
    metadata: std.ArrayList(t.Metadata),
    allocator: Allocator,
    /// The call this batch was started on, until its completion event is received.
    /// Not owned: the call must outlive the batch.
    call: ?*t.Call = null,

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

    /// Fails with `error.InvalidMetadata` for a key or value gRPC would refuse (see `errors.UsageError`).
    pub fn addMetadata(self: *Batch, key: []const u8, value: []const u8) error{ OutOfMemory, InvalidMetadata }!void {
        const k: t.Slice = try makeSlice(self.allocator, key);
        errdefer c.grpc_slice_unref(k);
        if (c.grpc_header_key_is_legal(k) == 0) return error.InvalidMetadata;
        const v: t.Slice = try makeSlice(self.allocator, value);
        errdefer c.grpc_slice_unref(v);
        if (c.grpc_is_binary_header(k) == 0 and c.grpc_header_nonbin_value_is_legal(v) == 0)
            return error.InvalidMetadata;

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
            c.GRPC_CALL_OK => self.call = call,
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
    ///
    /// On `.timeout`, the batch is still in flight: wait again, or `cancel` it,
    /// before destroying the batch or the call.
    pub fn wait(self: *Batch, queue: *PluckQueue, deadline: Deadline) WaitError!Result {
        const event = queue.pluck(@ptrCast(self), deadline) orelse return error.QueueShutdown;
        if (event != .timeout) self.call = null;
        return switch (event) {
            .timeout => .timeout,
            .failure => .operation_failed,
            .success => if (self.status.code != c.GRPC_STATUS_OK)
                .{ .failure = .{
                    .code = self.status.code,
                    .details = asZigSlice(&self.status.details),
                } }
            else
                .{ .success = if (self.is_inbound_expected)
                    try self.getReceivedMessage()
                else
                    null },
        };
    }

    /// Cancel the call this batch was started on, and wait for the batch to complete.
    ///
    /// Until its completion event is received, gRPC still reads the message
    /// to send and writes the response and status into the batch.
    /// Cancelling the call completes every batch in flight on it, but only this
    /// batch's event is received here. Does nothing if this batch is not in flight.
    pub fn cancel(self: *Batch, queue: *PluckQueue) void {
        const call = self.call orelse return;
        _ = c.grpc_call_cancel(call, null);
        _ = queue.pluck(@ptrCast(self), .infinite);
        self.call = null;
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
        // Received from the server, so allocated by gRPC, out of reach of Zig's leak detection
        c.grpc_slice_unref(self.status.details);
        if (self.status.description) |description| c.gpr_free(description);
        c.grpc_metadata_array_destroy(&self.status.leading_metadata);
        c.grpc_metadata_array_destroy(&self.status.trailing_metadata);
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
    options: CallOptions,
) RawCallError!Batch.Result {
    const call = channel.createCall(queue, path, options.deadline);
    defer c.grpc_call_unref(call);

    var batch: Batch = .init(allocator);
    defer batch.deinit();
    for (options.metadata) |m| try batch.addMetadata(m.key, m.value);
    try batch.setMessageToSend(data);
    batch.expectReceivedMessage();
    try batch.start(call);

    return switch (try batch.wait(queue, options.deadline)) {
        .timeout => {
            batch.cancel(queue);
            return .timeout;
        },
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

test "a timed out batch can be cancelled" {
    root.init();
    defer root.deinit();

    // The kernel completes TCP handshakes on a listening socket, but nothing ever answers
    const io = std.testing.io;
    const address: std.Io.net.IpAddress = try .parse("127.0.0.1", 0);
    var server = try address.listen(io, .{});
    defer server.deinit(io);

    var target_buffer: [32]u8 = undefined;
    const target = try std.fmt.bufPrintSentinel(&target_buffer, "127.0.0.1:{d}", .{server.socket.address.getPort()}, 0);

    var credentials: Credentials = .insecure();
    defer credentials.deinit();
    var channel: Channel = try .init(target, credentials);
    defer channel.deinit();
    var queue: PluckQueue = .init();
    defer queue.deinit();
    defer queue.shutdown();

    const call = channel.createCall(&queue, "/test.Service/Method", .{ .duration = .fromSeconds(30) });
    defer c.grpc_call_unref(call);

    var batch: Batch = .init(std.testing.allocator);
    defer batch.deinit();
    try batch.setMessageToSend("");
    batch.expectReceivedMessage();
    try batch.start(call);

    try std.testing.expectEqual(.timeout, try batch.wait(&queue, .{ .duration = .fromMilliseconds(100) }));
    batch.cancel(&queue);
    try std.testing.expectEqual(@as(c.grpc_status_code, c.GRPC_STATUS_CANCELLED), batch.status.code);
    // No longer in flight: there is no event left to wait for
    batch.cancel(&queue);
}

test "invalid metadata is rejected" {
    var batch: Batch = .init(std.testing.allocator);
    defer batch.deinit();

    try batch.addMetadata("authorization", "Bearer token");
    try batch.addMetadata("trace-proto-bin", "\x00\x01\n");
    try std.testing.expectError(error.InvalidMetadata, batch.addMetadata("Authorization", "Bearer token"));
    try std.testing.expectError(error.InvalidMetadata, batch.addMetadata("", "value"));
    try std.testing.expectError(error.InvalidMetadata, batch.addMetadata("key", "line\nbreak"));
    try std.testing.expectEqual(2, batch.metadata.items.len);
}
