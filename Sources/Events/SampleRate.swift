/// The fraction of events, or of groups of events, a `Sampler` (module `Trackers`) keeps: a
/// probability from 0, none, to 1, every one.
///
/// ```swift
/// let sampler = Sampler.events(of: Scrolled.self, rate: try SampleRate(0.1))
/// ```
///
/// A kept record carries the rate it was kept at as its ``SampleRateKey``, so a destination can
/// count it as `1 / value` records.
public struct SampleRate: Hashable, Sendable {
    /// The probability that a sampler keeps an event, or a group: 0 keeps none, 1 every one.
    public let value: Double

    /// The rate `value`.
    ///
    /// - Parameter value: The probability of keeping an event or a group.
    /// - Throws: ``InvalidSampleRate`` when `value` is below 0, above 1 or NaN.
    public init(_ value: Double) throws(InvalidSampleRate) {
        guard (0 ... 1).contains(value) else { throw InvalidSampleRate() }
        self.value = value
    }

    private init(product value: Double) {
        self.value = value
    }

    /// The rate of keeping what both this rate and `other` keep: their product, which is in
    /// 0 ... 1 as both are.
    package func multiplied(by other: SampleRate) -> SampleRate {
        SampleRate(product: value * other.value)
    }
}
