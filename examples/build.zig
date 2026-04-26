const std = @import("std");
const zon = @import("build.zig.zon");
const name = @tagName(zon.name);

const RunProtocStep = @import("protobuf").RunProtocStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const grpc = b.dependency("grpc", .{ .target = target, .optimize = optimize });
    const protobuf = b.dependency("protobuf", .{ .target = target, .optimize = optimize });
    const otelproto = b.dependency("otelproto", .{});

    const run_protoc = RunProtocStep.create(protobuf.builder, target, .{
        .destination_directory = b.path(""),
        .source_files = &.{b.path("helloworld.proto")},
        .include_directories = &.{b.path("")},
    });
    const mod = b.createModule(.{
        .root_source_file = b.path("greeter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protobuf", .module = protobuf.module("protobuf") },
            .{ .name = "cgrpc_wrapper", .module = grpc.module("cgrpc_wrapper") },
        },
    });
    const exe = b.addExecutable(.{
        .name = "greeter_client",
        .root_module = mod,
    });
    exe.step.dependOn(&run_protoc.step);
    b.installArtifact(exe);

    { // Build info
        const build_info = b.addOptions();
        build_info.addOption([]const u8, "version", zon.version);
        build_info.addOption([]const u8, "name", "greeter_client");
        mod.addOptions("build_info", build_info);
    }

    const stub_mod = b.createModule(.{
        .root_source_file = b.path("greeter_stub.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protobuf", .module = protobuf.module("protobuf") },
            .{ .name = "cgrpc_wrapper", .module = grpc.module("cgrpc_wrapper") },
        },
    });
    const stub_exe = b.addExecutable(.{
        .name = "greeter_stub_client",
        .root_module = stub_mod,
    });
    stub_exe.step.dependOn(&run_protoc.step);
    b.installArtifact(stub_exe);

    { // Build info
        const build_info = b.addOptions();
        build_info.addOption([]const u8, "version", zon.version);
        build_info.addOption([]const u8, "name", "greeter_stub_client");
        stub_mod.addOptions("build_info", build_info);
    }

    // Generate from OpenTelemetry protobuf definitions
    const gen_proto = b.step("gen-proto", "Generate zig files from protocol buffer definitions");
    const run_protoc_otel = RunProtocStep.create(protobuf.builder, target, .{
        .destination_directory = b.path(""),
        .source_files = &.{
            otelproto.path("opentelemetry/proto/logs/v1/logs.proto"),
            otelproto.path("opentelemetry/proto/collector/logs/v1/logs_service.proto"),
        },
        .include_directories = &.{
            otelproto.path(""),
        },
    });
    gen_proto.dependOn(&run_protoc_otel.step);

    const otel_pipeline_mod = b.addModule("otel_pipeline", .{
        .root_source_file = b.path("otel_pipeline.zig"),
        .imports = &.{
            .{ .name = "protobuf", .module = protobuf.module("protobuf") },
        },
    });

    const otel_mod = b.createModule(.{
        .root_source_file = b.path("otel_logs.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cgrpc_wrapper", .module = grpc.module("cgrpc_wrapper") },
            .{ .name = "otel_pipeline", .module = otel_pipeline_mod },
        },
    });
    const otel_exe = b.addExecutable(.{
        .name = "otel_logs_client",
        .root_module = otel_mod,
    });
    otel_exe.step.dependOn(&run_protoc_otel.step);
    b.installArtifact(otel_exe);

    { // Build info
        const build_info = b.addOptions();
        build_info.addOption([]const u8, "version", zon.version);
        build_info.addOption([]const u8, "name", "otel_logs_client");
        otel_mod.addOptions("build_info", build_info);
    }
}
