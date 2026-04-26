const std = @import("std");
const zon = @import("build.zig.zon");
const name = @tagName(zon.name);

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const useSystemGrpc = b.systemIntegrationOption("grpc", .{});

    const grpc = if (useSystemGrpc) bind: {
        const include_all = b.addWriteFile("grpc_api.h",
            \\#include <grpc/grpc.h>
            \\#include <grpc/credentials.h>
            \\#include <grpc/byte_buffer_reader.h>
        );
        const grpc_capi = b.addTranslateC(.{
            .root_source_file = try include_all.getDirectory().join(b.allocator, "grpc_api.h"),
            .target = target,
            .optimize = optimize,
        });
        grpc_capi.linkSystemLibrary("grpc", .{});
        break :bind grpc_capi.createModule();
    } else b.dependency("grpc", .{ .target = target, .optimize = optimize }).module("cgrpc");

    const wrapper = b.addModule(name, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "cgrpc", .module = grpc }},
    });

    { // Testing
        const test_step = b.step("test", "Run unit tests");
        const unit_tests = b.addTest(.{ .root_module = wrapper });
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    }
    { // Documentation
        const docs_step = b.step("docs", "Build the project documentation");
        const docs_obj = b.addObject(.{
            .name = name,
            .root_module = wrapper,
        });
        const install_docs = b.addInstallDirectory(.{
            .source_dir = docs_obj.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });
        docs_step.dependOn(&install_docs.step);
    }
}
