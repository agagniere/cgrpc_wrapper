const c = @import("cgrpc");
const t = @import("types.zig");
const root = @import("root.zig");

const Deadline = root.Deadline;

/// Specifies the type of APIs to use to pop events from the completion queue
pub const Type = enum {
    /// Events are popped out by calling next() API ONLY
    next,
    /// Events are popped out by calling pluck() API ONLY
    pluck,
};

/// The result of an operation
///
/// The value of .failure and .success is the tag passed to grpc_call_start_batch etc to start this operation.
pub const Event = union(enum) {
    /// No event before timeout
    timeout: void,
    failure: *opaque {},
    success: *opaque {},
};

pub const CompletionQueue = struct {
    handle: *t.completion_queue,

    pub fn init(of_type: Type) CompletionQueue {
        return .{
            .handle = switch (of_type) {
                .next => c.grpc_completion_queue_create_for_next(null).?,
                .pluck => c.grpc_completion_queue_create_for_pluck(null).?,
            },
        };
    }

    /// Returns null when the queue is shuting down and all events have been drained
    pub fn next(self: *CompletionQueue, deadline: Deadline) ?Event {
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
    pub fn shutdown(self: *CompletionQueue) void {
        c.grpc_completion_queue_shutdown(self.handle);
    }

    /// Destroy a completion queue.
    ///
    /// The caller must ensure that the queue is drained and
    /// no threads are executing next()
    ///
    /// TL;DR: Fist call shutdown, then drain all calls, then call deinit()
    pub fn deinit(self: *CompletionQueue) void {
        c.grpc_completion_queue_destroy(self.handle);
    }
};
