const c = @import("cgrpc");
const t = @import("types.zig");
const root = @import("root.zig");

const Deadline = root.Deadline;

/// The result of an operation
///
/// The value of .failure and .success is the tag passed to grpc_call_start_batch etc to start this operation.
pub const Event = union(enum) {
    /// No event before timeout
    timeout: void,
    failure: *opaque {},
    success: *opaque {},
};

/// Completion queue where events are popped using next().
/// Incompatible with pluck().
pub const NextQueue = struct {
    handle: *t.CompletionQueue,

    pub fn init() NextQueue {
        return .{ .handle = c.grpc_completion_queue_create_for_next(null).? };
    }

    /// Returns null when the queue is shutting down and all events have been drained.
    pub fn next(self: *NextQueue, deadline: Deadline) ?Event {
        const event = c.grpc_completion_queue_next(self.handle, deadline.toGprTimespec(), null);
        return switch (event.type) {
            c.GRPC_QUEUE_SHUTDOWN => null,
            c.GRPC_QUEUE_TIMEOUT => .timeout,
            else => if (event.success == 0)
                .{ .failure = @ptrCast(event.tag) }
            else
                .{ .success = @ptrCast(event.tag) },
        };
    }

    /// Begin destruction of a completion queue.
    ///
    /// Once all possible events are drained then next() will start to produce
    /// SHUTDOWN events only. At that point it's safe to call deinit.
    ///
    /// After calling this function applications should ensure that no
    /// NEW work is added to be published on this completion queue.
    pub fn shutdown(self: *NextQueue) void {
        c.grpc_completion_queue_shutdown(self.handle);
    }

    /// Destroy a completion queue.
    ///
    /// The caller must ensure that the queue is drained and
    /// no threads are executing next()
    ///
    /// TL;DR: First call shutdown, then drain all calls, then call deinit()
    pub fn deinit(self: *NextQueue) void {
        c.grpc_completion_queue_destroy(self.handle);
    }
};

/// Completion queue where events are popped using pluck().
/// Incompatible with next().
pub const PluckQueue = struct {
    handle: *t.CompletionQueue,

    pub fn init() PluckQueue {
        return .{ .handle = c.grpc_completion_queue_create_for_pluck(null).? };
    }

    /// Returns null when the queue is shutting down and all events have been drained.
    /// Unlike next(), waits specifically for the event associated with the given tag,
    /// allowing other batches' events to remain in the queue undisturbed.
    pub fn pluck(self: *PluckQueue, tag: *anyopaque, deadline: Deadline) ?Event {
        const event = c.grpc_completion_queue_pluck(self.handle, tag, deadline.toGprTimespec(), null);
        return switch (event.type) {
            c.GRPC_QUEUE_SHUTDOWN => null,
            c.GRPC_QUEUE_TIMEOUT => .timeout,
            else => if (event.success == 0)
                .{ .failure = @ptrCast(event.tag) }
            else
                .{ .success = @ptrCast(event.tag) },
        };
    }

    /// Begin destruction of a completion queue.
    ///
    /// After calling this function applications should ensure that no
    /// NEW work is added to be published on this completion queue.
    pub fn shutdown(self: *PluckQueue) void {
        c.grpc_completion_queue_shutdown(self.handle);
    }

    /// Destroy a completion queue.
    ///
    /// The caller must ensure that the queue is drained and
    /// no threads are executing pluck()
    pub fn deinit(self: *PluckQueue) void {
        c.grpc_completion_queue_destroy(self.handle);
    }
};
