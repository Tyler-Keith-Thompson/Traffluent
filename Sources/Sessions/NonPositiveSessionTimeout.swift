/// The error `Enricher.sessions(timeout:kinds:)` throws for a timeout of zero or less.
public struct NonPositiveSessionTimeout: Error, Hashable, Sendable {
    /// The error.
    public init() {}
}
