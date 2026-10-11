const std = @import("std");
const zon = @import("build.zig.zon");
const name = @tagName(zon.name);

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Linked to either a libgrpc built from source, or the system's one with `-fsys=grpc`
    const grpc = b.dependency("grpc", .{ .target = target, .optimize = optimize }).module("cgrpc");

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
        // Generating docs only needs the C API declarations, but `cgrpc` links
        // libgrpc, which would make the docs build it. Use the same translated
        // bindings through a module that doesn't link anything.
        const grpc_decls = b.createModule(.{
            .root_source_file = grpc.root_source_file,
            .target = grpc.resolved_target,
            .optimize = grpc.optimize,
            .link_libc = grpc.link_libc,
        });

        const docs_step = b.step("docs", "Build the project documentation");
        const docs_obj = b.addObject(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "cgrpc", .module = grpc_decls }},
            }),
        });
        const install_docs = b.addInstallDirectory(.{
            .source_dir = docs_obj.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });
        docs_step.dependOn(&install_docs.step);
    }
}
