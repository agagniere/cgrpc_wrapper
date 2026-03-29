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

    var channel: grpc.Channel = try .initInsecure("localhost:50051");
    defer channel.deinit();

    var queue: grpc.PluckQueue = .init();
    defer queue.deinit();
    defer queue.shutdown();

    var stub: grpc.Stub(protocol.Greeter) = .{
        .channel = &channel,
        .queue = &queue,
        .allocator = init.gpa,
    };

    const request: protocol.HelloRequest = .{ .name = "Ziguana" };
    var reply = try stub.call(.SayHello, request, .{
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
