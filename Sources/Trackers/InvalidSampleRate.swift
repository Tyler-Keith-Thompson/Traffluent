/// The error ``SampleRate/init(checked:)`` throws for a rate below 0, above 1 or NaN.
public struct InvalidSampleRate: Error, Hashable, Sendable {
    /// The error.
    public init() {}
}
