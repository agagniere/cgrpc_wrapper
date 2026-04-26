const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const grpc = @import("cgrpc_wrapper");
const protobuf = @import("protobuf");
const protocol = @import("helloworld.pb.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn main() !u8 {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

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

    const greet_call = channel.createCall(
        &queue,
        "/helloworld.Greeter/SayHello",
        .{ .duration = .fromSeconds(1) },
    );

    const name: protocol.HelloRequest = .{ .name = "Ziguana" };
    var encoded_name: Io.Writer.Allocating = .init(gpa);
    defer encoded_name.deinit();
    try name.encode(&encoded_name.writer, gpa);

    var batch: grpc.client.Batch = .init(gpa);
    defer batch.deinit();
    try batch.addMetadata("binary.name", build_info.name);
    try batch.addMetadata("binary.version", build_info.version);
    try batch.addMetadata("zig.version", builtin.zig_version_string);
    try batch.setMessageToSend(encoded_name.written());
    batch.expectReceivedMessage();
    try batch.start(greet_call);

    switch (try batch.wait(&queue, .{ .duration = .fromSeconds(2) })) {
        .timeout => std.log.warn("timeout", .{}),
        .operation_failed => std.log.err("operation failed", .{}),
        .failure => |f| std.log.err("gRPC error {}: {s}", .{ f.code, f.details }),
        .success => |message| {
            if (message) |bytes| {
                defer batch.allocator.free(bytes);
                std.log.debug("Received {} bytes : {x}", .{ bytes.len, bytes });
                var reader: Io.Reader = .fixed(bytes);
                var response: protocol.HelloReply = try .decode(&reader, gpa);
                defer response.deinit(gpa);
                std.log.info("Reply : '{s}'", .{response.message});
                return 0;
            }
        },
    }
    return 1;
}
