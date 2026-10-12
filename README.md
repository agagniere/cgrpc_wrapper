# gRPC Zig wrapper

This wrapper is a zig interface over libgrpc's core library.

## Status

| Architecture \ OS | Linux | macOS |
|:------------------|:-----:|:-----:|
| `x86_64`          | ✅    | ✅    |
| `arm64`           | ✅    | ✅    |

| Branch name | Zig version        | gRPC version  |
|:------------|:-------------------|---------------|
| `master`    | `master`, `0.17.x` | `1.85.0-pre1` |
| `zig-0.16`  | `0.16.x`           | `1.84.0`      |
| `zig-0.15`  | `0.15.x`           | `1.80.0`      |

## Use

Add the dependency to your `build.zig.zon` by running the following command:
```shell
zig fetch --save git+https://github.com/agagniere/cgrpc_wrapper#master
```

Then, in your `build.zig`:
```zig
const grpc = b.dependency("cgrpc_wrapper", .{
    .target = target,
    .optimize = optimize,
});

mod.addImport("grpc", grpc.module("cgrpc_wrapper"));
```

## Linking

By default, libgrpc is linked statically, producing self-contained binaries.

To link it dynamically instead, pass `.link_mode = .dynamic`, and install libgrpc in `lib/`, next to the binaries in `bin/`.
For example, to let the linking mode be chosen when building:
```zig
const grpc_link_mode = b.option(std.builtin.LinkMode, "grpc_link_mode", "Link libgrpc statically or dynamically");

const grpc = b.dependency("cgrpc_wrapper", .{
    .target = target,
    .optimize = optimize,
    .link_mode = grpc_link_mode,
});

mod.addImport("grpc", grpc.module("cgrpc_wrapper"));
if (!b.systemIntegrationOption("grpc", .{})) {
    const libgrpc = grpc.artifact("grpc");
    if (libgrpc.isDynamicLibrary())
        b.installArtifact(libgrpc);
}
```

Binaries are given an rpath that finds it there (`$ORIGIN/../lib`, or `@executable_path/../lib` on macOS).

## System Integration

By default, libgrpc is provided from a zig package, to allow cross-compilation and reproducibility.

However, for security reasons, or to not waste disk / CPU / time re-compiling a huge library already installed on the system, it might be preferable to use the system's `.so`/`.dylib`.

For this purpose, a system integration is available. When building the final binary:

```shell
zig build -fsys=grpc
```

will use the system's gRPC library, and nothing gets downloaded or built.
The `grpc` artifact is not available in this mode, which is why, in the snippet above,
system integration is checked before installing the shared library.

## Authentication

Available types of client credentials:
- insecure
- local Unix Domain Socket
- local TCP
- SSL, with the root certificate provided either:
  - as a string
  - or as a file using `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH` environment variable
