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

    /// A message compression algorithm.
    ///
    /// Only affects messages sent by this client: gRPC decompresses what it receives
    /// whatever the algorithm, as long as it supports it.
    pub const Compression = enum(c_int) {
        none = c.GRPC_COMPRESS_NONE,
        deflate = c.GRPC_COMPRESS_DEFLATE,
        gzip = c.GRPC_COMPRESS_GZIP,

        /// The name gRPC sends in `grpc-encoding` (`identity` for `.none`).
        /// Same as `grpc_compression_algorithm_name`, whose header is not part of `cgrpc`.
        pub fn name(self: Compression) [:0]const u8 {
            return switch (self) {
                .none => "identity",
                .deflate => "deflate",
                .gzip => "gzip",
            };
        }
    };

    pub const Options = struct {
        /// Compression of every message sent on this channel, unless a call overrides it
        /// (see `CallOptions.compression`).
        compression: Compression = .none,
    };

    pub fn init(target: [*:0]const u8, credentials: Credentials, options: Options) InitError!Channel {
        // Other possible args:
        // https://github.com/grpc/grpc/blob/v1.85.x/include/grpc/impl/channel_arg_names.h
        var storage: [max_args]t.ChannelArgument = undefined;
        const args = asGRPCChannelArguments(fillChannelArguments(options, &storage));
        return if (c.grpc_channel_create(target, credentials.handle, &args)) |chan|
            .{ .handle = chan }
        else
            error.UnableToCreateChannel;
    }

    /// The most args the options can add, assuming each option adds at most one.
    const max_args = std.meta.fieldNames(Options).len;

    /// Translate options into gRPC args, written to `storage`: it must have room for `max_args`.
    /// Returns the part of `storage` that was used.
    fn fillChannelArguments(options: Options, storage: []t.ChannelArgument) []t.ChannelArgument {
        var args: std.ArrayList(t.ChannelArgument) = .initBuffer(storage);
        if (options.compression != .none) args.appendAssumeCapacity(.{
            .type = c.GRPC_ARG_INTEGER,
            .key = @ptrCast(@constCast(c.GRPC_COMPRESSION_CHANNEL_DEFAULT_ALGORITHM)),
            .value = .{ .integer = @backingInt(options.compression) },
        });
        return args.items;
    }

    /// A view of `args` as gRPC expects them: it only lives as long as `args`.
    fn asGRPCChannelArguments(args: []t.ChannelArgument) t.ChannelArguments {
        return .{ .num_args = args.len, .args = args.ptr };
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

test "compression names are those of the grpc-encoding header" {
    try std.testing.expectEqualStrings("identity", Channel.Compression.none.name());
    try std.testing.expectEqualStrings("deflate", Channel.Compression.deflate.name());
    try std.testing.expectEqualStrings("gzip", Channel.Compression.gzip.name());
}

test "compression is passed as the default algorithm of the channel" {
    var storage: [Channel.max_args]t.ChannelArgument = undefined;

    const none = Channel.fillChannelArguments(.{}, &storage);
    try std.testing.expectEqual(0, none.len);

    const gzip = Channel.fillChannelArguments(.{ .compression = .gzip }, &storage);
    try std.testing.expectEqual(1, gzip.len);
    const arg = gzip[0];
    try std.testing.expectEqualStrings("grpc.default_compression_algorithm", std.mem.span(arg.key));
    try std.testing.expectEqual(@as(@TypeOf(arg.type), c.GRPC_ARG_INTEGER), arg.type);
    try std.testing.expectEqual(c.GRPC_COMPRESS_GZIP, arg.value.integer);

    const view = Channel.asGRPCChannelArguments(gzip);
    try std.testing.expectEqual(1, view.num_args);
    try std.testing.expectEqual(gzip.ptr, view.args);
}

test "a channel can be created with compression" {
    root.init();
    defer root.deinit();

    var credentials: Credentials = .insecure();
    defer credentials.deinit();
    var channel: Channel = try .init("127.0.0.1:1", credentials, .{ .compression = .gzip });
    defer channel.deinit();
}
