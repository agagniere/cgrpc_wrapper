const c = @import("cgrpc");

/// The Channel interface allows creation of Call objects.
pub const Channel = c.grpc_channel;
/// A channel credentials object represents a way to authenticate a client on a channel.
pub const ChannelCredentials = c.grpc_channel_credentials;
/// A Call represents an RPC. When created, it is in a configuration state
/// allowing properties to be set until it is invoked. After invoke, the Call
/// can have messages written to it and read from it.
pub const Call = c.grpc_call;
/// Completion Queues enable notification of the completion of asynchronous actions.
pub const CompletionQueue = c.grpc_completion_queue;
pub const RegisteredCall = opaque {};
pub const ByteBuffer = c.grpc_byte_buffer;
pub const Operation = c.grpc_op;
/// A grpc_slice s, if initialized, represents the byte range s.bytes[0..s.length-1].
pub const Slice = c.grpc_slice;
pub const Timespec = c.gpr_timespec;
/// A single metadata element
pub const Metadata = c.grpc_metadata;
/// Object that holds a private key / certificate chain pair in PEM format.
pub const SslKeyCertPair = c.grpc_ssl_pem_key_cert_pair;
/// Object that holds additional peer-verification options on a secure channel.
pub const SslVerifyPeerOptions = c.grpc_ssl_verify_peer_options;
