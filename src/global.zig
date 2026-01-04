const c = @import("cgrpc");

/// Initialize the grpc library.
///
/// After it's called, a matching invocation to grpc_shutdown() is expected.
/// It is not safe to call any other grpc functions before calling this.
pub fn init() void {
    c.grpc_init();
}

/// Shut down the grpc library.
///
/// The last call to grpc_shutdown will initiate cleaning up of grpc library
/// internals, which can happen in another thread. Once the clean-up is done,
/// no memory is used by grpc, nor are any instructions executing within the
/// grpc library.  Prior to calling, all application owned grpc objects must
/// have been destroyed.
pub fn deinit() void {
    c.grpc_shutdown();
}

/// Return a C-string representing the current version of grpc
pub fn version() [*:0]const u8 {
    return c.grpc_version_string();
}

/// Return a C-string specifying what the 'g' in gRPC stands for
///
/// Each gRPC version uses a different G-word as its nickname
pub fn gStandsFor() [*:0]const u8 {
    return c.grpc_g_stands_for();
}
