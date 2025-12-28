const std = @import("std");
const zon = @import("build.zig.zon");
const name = @tagName(zon.name);

const RunProtocStep = @import("protobuf").RunProtocStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const grpc = b.dependency("grpc", .{});
    const protobuf = b.dependency("protobuf", .{ .target = target, .optimize = optimize });

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
}
