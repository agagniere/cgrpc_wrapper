# gRPC Zig wrapper

This wrapper is a zig interface over libgrpc's core library.

## Status

| Architecture \ OS | Linux | MacOS |
|:------------------|:-----:|:-----:|
| `x86_64`          | ✅    | ✅    |
| `arm64`           | ✅    | ✅    |

| Branch name | Zig version        |
|:------------|:-------------------|
| `master`    | `0.16.x`, `master` |
| `zig-0.15`  | `0.15.x`           |

## Use

Add the dependency to your `build.zig.zon` by running the following command:
```zig
zig fetch --save git+https://github.com/agagniere/cgrpc_wrapper#master
```

Then, in your `build.zig`:
```zig
const grpc = b.dependency("cgrpc_wrapper", {
    .target = target,
    .optimize = optimize,
});

mod.addImport("grpc", grpc.module("cgrpc_wrapper"));
```

## System Integration

By default, libgrpc is provided from a zig package, to allow cross-compilation and reproducibility.

However, for security reason, or to not waste disk / CPU / time re-compiling a huge library already installed on the system, it might be preferable to use the system's `.so`/`.dylib`

For this purpose, a system integration is available. When building the final binary:

```shell
zig build -fsys=grpc
```

will use the system's gRPC library.

## Authentication

Available types of client credentials:
- insecure
- local Unix Domain Socket
- local TCP
- SSL, with the root certificate provided either:
  - as a string
  - or as a file using `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH` environment variable
