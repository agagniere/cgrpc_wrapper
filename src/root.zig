const std = @import("std");
const global = @import("global.zig");
pub const client = @import("client.zig");

pub const Deadline = @import("time.zig").Deadline;
pub const NextQueue = @import("queue.zig").NextQueue;
pub const PluckQueue = @import("queue.zig").PluckQueue;
pub const Channel = @import("channel.zig").Channel;

pub const init = global.init;
pub const deinit = global.deinit;
pub const version = global.version;
pub const gStandsFor = global.gStandsFor;

test {
    _ = @import("slice.zig");

    std.testing.refAllDecls(@This());
}
