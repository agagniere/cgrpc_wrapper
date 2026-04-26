const std = @import("std");

const root = @import("root.zig");
const c = @import("cgrpc");
const t = @import("types.zig");

const Deadline = root.Deadline;
const Credentials = root.client.Credentials;

pub const Channel = struct {
    handle: *t.Channel,

    pub const InitError = error{
        /// gRPC failed to create a channel to the given target.
        UnableToCreateChannel,
    };

    pub fn init(target: [*:0]const u8, credentials: Credentials) InitError!Channel {
        // Passing no args for now. Will we want customization ? Possible args:
        // https://github.com/grpc/grpc/blob/v1.80.x/include/grpc/impl/channel_arg_names.h
        return if (c.grpc_channel_create(target, credentials.handle, null)) |chan|
            .{ .handle = chan }
        else
            error.UnableToCreateChannel;
    }

    pub fn createCall(
        self: *Channel,
        queue: anytype,
        method: []const u8,
        deadline: Deadline,
    ) *t.Call {
        // A comment says:
        // "'method' and 'host' need only live through the invocation of this function."
        const method_slice = c.grpc_slice_from_static_buffer(method.ptr, method.len);

        return c.grpc_channel_create_call(
            self.handle,
            null,
            0,
            queue.handle,
            method_slice,
            null,
            deadline.toGprTimespec(),
            null,
        ).?;
    }

    pub fn deinit(self: *Channel) void {
        c.grpc_channel_destroy(self.handle);
    }
};
