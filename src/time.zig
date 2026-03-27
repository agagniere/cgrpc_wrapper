const std = @import("std");
const c = @import("cgrpc");
const t = @import("types.zig");

/// Deadlines are either specified using an absolute timestamp
/// or a relative timespan
pub const Deadline = union(enum) {
    /// Nanoseconds since Unix epoch
    timestamp: i128,
    /// Nanoseconds
    duration: i128,

    pub fn toGprTimespec(self: Deadline) t.Timespec {
        return switch (self) {
            .timestamp => |ns| .{
                .tv_sec = @intCast(@divTrunc(ns, std.time.ns_per_s)),
                .tv_nsec = @intCast(@mod(ns, std.time.ns_per_s)),
                .clock_type = c.GPR_CLOCK_REALTIME,
            },
            .duration => |ns| .{
                .tv_sec = @intCast(@divTrunc(ns, std.time.ns_per_s)),
                .tv_nsec = @intCast(@mod(ns, std.time.ns_per_s)),
                .clock_type = c.GPR_TIMESPAN,
            },
        };
    }
};
