const std = @import("std");
const global = @import("global.zig");
const queue = @import("queue.zig");

pub const client = @import("client.zig");
pub const errors = @import("errors.zig");
pub const Deadline = @import("time.zig").Deadline;
pub const NextQueue = queue.NextQueue;
pub const PluckQueue = queue.PluckQueue;
pub const Channel = @import("channel.zig").Channel;
pub const Stub = @import("stub.zig").Stub;

pub const init = global.init;
pub const deinit = global.deinit;
pub const version = global.version;
pub const gStandsFor = global.gStandsFor;

test {
    _ = @import("slice.zig");

    std.testing.refAllDecls(@This());
}
