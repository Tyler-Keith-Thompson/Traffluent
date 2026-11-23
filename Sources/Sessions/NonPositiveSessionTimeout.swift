/// The error `Enricher.sessions(checkedTimeout:kinds:)` throws for a timeout of zero or less.
public struct NonPositiveSessionTimeout: Error, Hashable, Sendable {
    /// The error.
    public init() {}
}
