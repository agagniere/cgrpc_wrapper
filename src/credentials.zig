const std = @import("std");

const root = @import("root.zig");
const c = @import("cgrpc");
const t = @import("types.zig");

const SslKeyCertPair = extern struct {
    /// PEM encoding of the client's private key.
    private_key: [*:0]const u8,
    /// PEM encoding of the client's certificate chain.
    certificate_chain: [*:0]const u8,
};

pub const ChannelCredentials = struct {
    handle: *t.ChannelCredentials,

    /// The security level of the resulting connection is GRPC_SECURITY_NONE
    pub fn insecure() ChannelCredentials {
        return .{ .handle = c.grpc_insecure_credentials_create().? };
    }

    /// The security level of the resulting connection is GRPC_SECURITY_NONE
    pub fn localTCP() ChannelCredentials {
        return .{ .handle = c.grpc_local_credentials_create(c.LOCAL_TCP).? };
    }

    /// The security level of the resulting connection is GRPC_PRIVACY_AND_INTEGRITY
    pub fn localUDS() ChannelCredentials {
        return .{ .handle = c.grpc_local_credentials_create(c.UDS).? };
    }

    /// Creates an SSL credentials object.
    /// The security level of the resulting connection is GRPC_PRIVACY_AND_INTEGRITY.
    /// - pem_root_certs is the NULL-terminated string containing the PEM encoding
    ///   of the server root certificates. If this parameter is NULL, the
    ///   implementation will first try to dereference the file pointed by the
    ///   GRPC_DEFAULT_SSL_ROOTS_FILE_PATH environment variable, and if that fails,
    ///   try to get the roots set by grpc_override_ssl_default_roots. Eventually,
    ///   if all these fail, it will try to get the roots from a well-known place on
    ///   disk (in the grpc install directory).
    ///   gRPC has implemented root cache if the underlying OpenSSL library supports
    ///   it. The gRPC root certificates cache is only applicable on the default
    ///   root certificates, which is used when this parameter is nullptr. If user
    ///   provides their own pem_root_certs, when creating an SSL credential object,
    ///   gRPC would not be able to cache it, and each subchannel will generate a
    ///   copy of the root store. So it is recommended to avoid providing large room
    ///   pem with pem_root_certs parameter to avoid excessive memory consumption,
    ///   particularly on mobile platforms such as iOS.
    /// - pem_key_cert_pair is a pointer on the object containing client's private
    ///   key and certificate chain. This parameter can be NULL if the client does
    ///   not have such a key/cert pair.
    // - verify_options is an optional verify_peer_options object which holds
    //   additional options controlling how peer certificates are verified. For
    //   example, you can supply a callback which receives the peer's certificate
    //   with which you can do additional verification. Can be NULL, in which
    //   case verification will retain default behavior. Any settings in
    //   verify_options are copied during this call, so the verify_options
    //   object can be released afterwards.
    pub fn ssl(root_certs_pem: ?[:0]const u8, key_cert_pair: ?*SslKeyCertPair) ChannelCredentials {
        return .{ .handle = c.grpc_ssl_credentials_create_ex(
            if (root_certs_pem) |cert| cert.ptr else null,
            @ptrCast(key_cert_pair),
            null,
            null,
        ).? };
    }

    pub fn deinit(self: *ChannelCredentials) void {
        c.grpc_channel_credentials_release(self.handle);
    }
};
