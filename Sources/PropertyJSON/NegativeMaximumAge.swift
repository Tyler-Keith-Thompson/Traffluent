/// A maximum age below zero, for a request's deadline that would pass before its oldest record was
/// tracked.
public struct NegativeMaximumAge: Error, Sendable, Hashable {
    /// The error.
    public init() {}
}
