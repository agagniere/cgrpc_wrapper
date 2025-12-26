const c = @import("cgrpc");

pub const channel = c.grpc_channel;
pub const channel_credentials = c.grpc_channel_credentials;
pub const call = c.grpc_call;
pub const completion_queue = c.grpc_completion_queue;
pub const registered_call = opaque {};
pub const byte_buffer = c.grpc_byte_buffer;
pub const operation = c.grpc_op;
pub const slice = c.grpc_slice;
pub const timespec = c.gpr_timespec;
pub const metadata = c.grpc_metadata;
