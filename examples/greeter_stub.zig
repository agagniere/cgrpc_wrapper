const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const grpc = @import("cgrpc_wrapper");
const protobuf = @import("protobuf");
const protocol = @import("helloworld.pb.zig");

pub fn main(init: std.process.Init) !void {
    grpc.init();
    defer grpc.deinit();
    std.log.info("Using gRPC ({s} Remote Procedure Call) version {s}", .{ grpc.gStandsFor(), grpc.version() });

    var credentials: grpc.client.Credentials = .localTCP();
    defer credentials.deinit();

    var channel: grpc.Channel = try .init("localhost:50051", credentials);
    defer channel.deinit();

    var queue: grpc.PluckQueue = .init();
    defer queue.deinit();
    defer queue.shutdown();

    var stub: grpc.Stub(protocol.Greeter) = .{
        .allocator = init.gpa,
        .channel = &channel,
        .queue = &queue,
    };

    var reply = try stub.call(.SayHello, .{ .name = "Ziguana" }, .{
        .deadline = .{ .duration = .fromSeconds(2) },
        .metadata = &.{
            .{ .key = "binary.name", .value = build_info.name },
            .{ .key = "binary.version", .value = build_info.version },
            .{ .key = "zig.version", .value = builtin.zig_version_string },
        },
    });
    defer reply.deinit(init.gpa);

    std.log.info("Reply : '{s}'", .{reply.message});
}
