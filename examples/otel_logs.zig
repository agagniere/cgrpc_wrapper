const std = @import("std");
const builtin = @import("builtin");
const build_info = @import("build_info");
const grpc = @import("cgrpc_wrapper");
const otelData = @import("otel_pipeline");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const LogsBatch = otelData.Logs.LogsData;

pub fn main(init: std.process.Init) !u8 {
    grpc.init();
    defer grpc.deinit();
    std.log.info("Using gRPC ({s} Remote Procedure Call) version {s}", .{ grpc.gStandsFor(), grpc.version() });

    var credentials: grpc.client.Credentials = .localTCP();
    defer credentials.deinit();

    var channel: grpc.Channel = try .init("localhost:4317", credentials);
    defer channel.deinit();

    var queue: grpc.PluckQueue = .init();
    defer queue.deinit();
    defer queue.shutdown();

    var stub: grpc.Stub(otelData.LogsCollector.LogsService) = .{
        .channel = &channel,
        .queue = &queue,
        .allocator = init.gpa,
    };

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const logs = try generateLogs(arena.allocator(), init.io);

    var reply = stub.call(
        .Export,
        .{ .resource_logs = logs.resource_logs },
        .{ .deadline = .{ .duration = .fromSeconds(3) }, .metadata = &.{
            .{ .key = "binary.name", .value = build_info.name },
            .{ .key = "binary.version", .value = build_info.version },
            .{ .key = "zig.version", .value = builtin.zig_version_string },
        } },
    ) catch |err| {
        std.log.err("gRPC call failed: {t}", .{err});
        return 1;
    };
    defer reply.deinit(init.gpa);

    if (reply.partial_success) |ps| {
        if (ps.rejected_log_records > 0) {
            std.log.warn("Server rejected {} log records: {s}", .{ ps.rejected_log_records, ps.error_message });
        } else if (ps.error_message.len > 0) {
            std.log.warn("Server note: {s}", .{ps.error_message});
        }
    }
    std.log.info("Logs exported successfully", .{});
    return 0;
}

fn generateLogs(alloc: Allocator, io: Io) !LogsBatch {
    var batch: LogsBatch = .{};

    var logs_from_host = try batch.resource_logs.addOne(alloc);
    logs_from_host.* = .{};
    logs_from_host.resource = .{};
    try logs_from_host.resource.?.attributes.append(alloc, .{ .key = "service.name", .value = .{ .value = .{ .string_value = build_info.name } } });
    try logs_from_host.resource.?.attributes.append(alloc, .{ .key = "service.version", .value = .{ .value = .{ .string_value = build_info.version } } });
    try logs_from_host.resource.?.attributes.append(alloc, .{ .key = "language", .value = .{ .value = .{ .string_value = "zig" } } });
    try logs_from_host.resource.?.attributes.append(alloc, .{ .key = "zig.version", .value = .{ .value = .{ .string_value = builtin.zig_version_string } } });

    const location = @src();
    var logs_from_instance = try logs_from_host.scope_logs.addOne(alloc);
    logs_from_instance.* = .{};
    logs_from_instance.scope = .{ .name = location.fn_name, .version = build_info.version };
    try logs_from_instance.scope.?.attributes.append(alloc, .{ .key = "file", .value = .{ .value = .{ .string_value = location.file } } });
    try logs_from_instance.scope.?.attributes.append(alloc, .{ .key = "transport", .value = .{ .value = .{ .string_value = "grpc" } } });
    try logs_from_instance.scope.?.attributes.append(alloc, .{ .key = "grpc.version", .value = .{ .value = .{ .string_value = std.mem.span(grpc.version()) } } });

    for (0..10) |i| {
        const now = std.Io.Clock.real.now(io);
        const now_ns: u64 = @intCast(now.toNanoseconds());
        const log: otelData.Logs.LogRecord = .{
            .time_unix_nano = now_ns,
            .observed_time_unix_nano = now_ns,
            .severity_number = @enumFromInt((i % 6) * 4 + 1),
            .body = .{ .value = .{ .string_value = "Hello from zig-grpc" } },
        };
        try logs_from_instance.log_records.append(alloc, log);
    }
    return batch;
}
