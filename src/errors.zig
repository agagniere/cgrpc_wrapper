/// Errors from incorrect API usage.
/// Receiving any of these indicates a bug in the caller.
pub const UsageError = error{
    /// Something failed, we don't know what
    Unknown,
    /// This method is not available on the server
    NotOnServer,
    /// This method is not available on the client
    NotOnClient,
    /// This method must be called before server_accept
    AlreadyAccepted,
    /// This method must be called before invoke
    AlreadyInvoked,
    /// This method must be called after invoke
    NotInvoked,
    /// This call is already finished (writes_done or write_status has already been called)
    AlreadyFinished,
    /// There is already an outstanding read/write operation on the call
    TooManyOperations,
    /// The flags value was illegal for this call
    InvalidFlags,
    /// Invalid metadata was passed to this call
    InvalidMetadata,
    /// Invalid message was passed to this call
    InvalidMessage,
    /// Completion queue for notification has not been registered with the server
    NotServerCompletionQueue,
    /// This batch of operations leads to more operations than allowed
    BatchTooBig,
    /// Payload type requested is not the type registered
    PayloadTypeMismatch,
    /// Completion queue has been shutdown
    CompletionQueueShutdown,
};

/// Errors that prevented the call from completing at the transport level.
pub const TransportError = error{
    /// No response received before the deadline expired.
    Timeout,
    /// The batch operation failed before a status was received.
    OperationFailed,
    /// The call succeeded but no response message was present.
    NoResponse,
    /// The completion queue was shut down before the call completed.
    QueueShutdown,
};

/// Non-OK status codes returned by the server.
pub const StatusError = error{
    /// The operation was cancelled, typically by the caller.
    Cancelled,
    /// Unknown error, or an error from a different error space.
    Unknown,
    /// The client specified an invalid argument.
    InvalidArgument,
    /// The deadline expired before the operation could complete.
    DeadlineExceeded,
    /// A requested entity was not found.
    NotFound,
    /// An entity that the client attempted to create already exists.
    AlreadyExists,
    /// The caller does not have permission to execute the operation.
    PermissionDenied,
    /// Some resource has been exhausted (quota, rate limit, disk space…).
    ResourceExhausted,
    /// The system is not in a state required for the operation.
    FailedPrecondition,
    /// The operation was aborted, typically due to a concurrency issue.
    Aborted,
    /// The operation was attempted past the valid range.
    OutOfRange,
    /// The operation is not implemented or not supported by this server.
    Unimplemented,
    /// Internal server error; some invariant was broken.
    Internal,
    /// The service is currently unavailable; retrying may succeed.
    Unavailable,
    /// Unrecoverable data loss or corruption.
    DataLoss,
    /// The request does not have valid authentication credentials.
    Unauthenticated,
    /// Unrecognized gRPC status code.
    GrpcError,
};
