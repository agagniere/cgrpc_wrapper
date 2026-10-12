const std = @import("std");
const zon = @import("build.zig.zon");
const name = @tagName(zon.name);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const link_mode = b.option(std.builtin.LinkMode, "link_mode", "Link libgrpc statically or dynamically");
    const pic = b.option(bool, "pic", "Produce Position Independent Code. Defaults to true when link_mode is dynamic");

    const grpc = b.dependency("grpc", .{
        .target = target,
        .optimize = optimize,
        .link_mode = link_mode,
        .pic = pic,
    });
    const libgrpc_built = if (b.systemIntegrationOption("grpc", .{})) null else grpc.artifact("grpc");
    // Dependent packages look libgrpc up through this package to find out whether to install it (when dynamic),
    // and `Dependency.artifact()` only finds artifacts installed by this package: install it in both modes
    if (libgrpc_built) |libgrpc| b.installArtifact(libgrpc);

    // Linked to either a libgrpc built from source, or the system's one with `-fsys=grpc`
    const cgrpc = grpc.module("cgrpc");
    const wrapper = b.addModule(name, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "cgrpc", .module = cgrpc }},
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
        const cgrpc_decls = b.createModule(.{
            .root_source_file = cgrpc.root_source_file,
            .target = cgrpc.resolved_target,
            .optimize = cgrpc.optimize,
            .link_libc = cgrpc.link_libc,
        });

        const docs_step = b.step("docs", "Build the project documentation");
        const docs_obj = b.addObject(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "cgrpc", .module = cgrpc_decls }},
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
