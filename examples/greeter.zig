const std = @import("std");
const builtin = @import("builtin");
const grpc = @import("cgrpc_wrapper");
const protobuf = @import("protobuf");
const protocol = @import("helloworld.pb.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var threaded: Io.Threaded = .init(gpa);
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

    var queue: grpc.CompletionQueue = .init(.next);
    defer queue.deinit();

    const greet_call = channel.createCall(
        &queue,
        "/helloworld.Greeter/SayHello",
        .{ .duration = .fromSeconds(1) },
    );

    const name: protocol.HelloRequest = .{ .name = "Ziguana" };
    var encoded_name: Io.Writer.Allocating = .init(gpa);
    defer encoded_name.deinit();
    try name.encode(&encoded_name.writer, gpa);

    var batch: grpc.client.Batch = try .init(gpa);
    defer batch.deinit();
    try batch.addMetadata("custom-string", "Foo_bar-baz:toto");
    try batch.addMessageToSend(encoded_name.written());
    try batch.expectReceivedMessage();
    var status: grpc.client.Batch.Status = .{};
    try batch.start(greet_call, @ptrCast(&batch), &status);

    queue.shutdown();
    while (queue.next(.{ .duration = .fromSeconds(1) })) |event| {
        switch (event) {
            .timeout => {
                std.log.warn("timeout", .{});
            },
            .failure => |tag| {
                std.log.err("Batch failed: {x}", .{@intFromPtr(tag)});
            },
            .success => |tag| {
                std.log.debug("Batch complete: {x}", .{@intFromPtr(tag)});
                std.debug.assert(&batch == @as(*grpc.client.Batch, @ptrCast(@alignCast(tag))));
                while (try batch.nextReceivedMessage()) |message| {
                    std.log.info("Received {} bytes : {x}", .{ message.len, message });
                    defer batch.allocator.free(message);
                    var reader: Io.Reader = .fixed(message);
                    var response: protocol.HelloReply = try .decode(&reader, gpa);
                    defer response.deinit(gpa);
                    std.log.info("Reply : '{s}'", .{response.message});
                }
            },
        }
    }
}
