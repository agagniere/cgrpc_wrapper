const c = @import("cgrpc");

pub const Channel = c.grpc_channel;
pub const ChannelCredentials = c.grpc_channel_credentials;
pub const Call = c.grpc_call;
pub const CompletionQueue = c.grpc_completion_queue;
pub const RegisteredCall = opaque {};
pub const ByteBuffer = c.grpc_byte_buffer;
pub const Operation = c.grpc_op;
pub const Slice = c.grpc_slice;
pub const Timespec = c.gpr_timespec;
pub const Metadata = c.grpc_metadata;
