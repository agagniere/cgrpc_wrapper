# gRPC Zig wrapper

This wrapper is a zig interface over libgrpc's core library.

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

## Authentication

Available types of client credentials:
- insecure
- local Unix Domain Socket
- local TCP
- SSL, with the root certificate provided either:
  - as a string
  - or as a file using `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH` environment variable
