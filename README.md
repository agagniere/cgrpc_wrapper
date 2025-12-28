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
