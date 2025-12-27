const std = @import("std");

const c = @import("cgrpc");
const t = @import("types.zig");
const Deadline = @import("time.zig").Deadline;

pub const Channel = struct {
    credentials: *t.ChannelCredentials,
    handle: *t.Channel,

    pub fn initInsecure(target: [*:0]const u8) !Channel {
        const creds = c.grpc_insecure_credentials_create().?;
        errdefer c.grpc_channel_credentials_release(creds);

        return if (c.grpc_channel_create(target, creds, null)) |chan|
            .{ .credentials = creds, .handle = chan }
        else
            error.UnableToCreateChannel;
    }

    pub fn createCall(
        self: *Channel,
        queue: *CompletionQueue,
        method: []const u8,
        deadline: Deadline,
    ) *t.call {
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
        c.grpc_channel_credentials_release(self.credentials);
    }
};
