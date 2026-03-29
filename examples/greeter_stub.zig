const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const grpc = @import("cgrpc_wrapper");
const protobuf = @import("protobuf");
const protocol = @import("helloworld.pb.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var threaded: Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    return juicyMain(gpa, io);
}

pub fn juicyMain(gpa: Allocator, io: Io) !void {
    _ = io;
    grpc.init();
    defer grpc.deinit();
    std.log.info("Using gRPC ({s} Remote Procedure Call) version {s}", .{ grpc.gStandsFor(), grpc.version() });

    var channel: grpc.Channel = try .initInsecure("localhost:50051");
    defer channel.deinit();

    var queue: grpc.PluckQueue = .init();
    defer queue.deinit();

    var stub: grpc.Stub(protocol.Greeter) = .{
        .channel = &channel,
        .queue = &queue,
        .allocator = gpa,
    };

    const request: protocol.HelloRequest = .{ .name = "Ziguana" };
    var reply = try stub.call("SayHello", request, .{ .duration = .fromSeconds(2) });
    defer reply.deinit(gpa);

    std.log.info("Reply : '{s}'", .{reply.message});

    queue.shutdown();
}
