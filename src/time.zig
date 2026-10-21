const std = @import("std");
const c = @import("cgrpc");
const t = @import("types.zig");

const Io = std.Io;

/// Deadlines are either specified using an absolute timestamp
/// or a relative timespan, or never elapse
pub const Deadline = union(enum) {
    timestamp: Io.Timestamp,
    duration: Io.Duration,
    infinite,

    pub fn toGprTimespec(self: Deadline) t.Timespec {
        return switch (self) {
            .timestamp => |timestamp| .{
                .tv_sec = timestamp.toSeconds(),
                .tv_nsec = @truncate(@mod(timestamp.toNanoseconds(), std.time.ns_per_s)),
                .clock_type = c.GPR_CLOCK_REALTIME,
            },
            .duration => |duration| .{
                .tv_sec = duration.toSeconds(),
                .tv_nsec = @truncate(@mod(duration.toNanoseconds(), std.time.ns_per_s)),
                .clock_type = c.GPR_TIMESPAN,
            },
            .infinite => c.gpr_inf_future(c.GPR_CLOCK_REALTIME),
        };
    }
};
