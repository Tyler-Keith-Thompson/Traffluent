/// The error ``TransientStatus/init(_:)`` throws for a status that is neither a client error
/// (4xx) nor a server error (5xx).
public struct InvalidTransientStatus: Error, Hashable, Sendable {
    /// The error.
    public init() {}
}
