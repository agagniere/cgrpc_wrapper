const std = @import("std");
const zon = @import("build.zig.zon");
const name = @tagName(zon.name);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const grpc = b.dependency("grpc", .{ .target = target, .optimize = optimize });

    const wrapper = b.addModule(name, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "cgrpc", .module = grpc.module("cgrpc") }},
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
