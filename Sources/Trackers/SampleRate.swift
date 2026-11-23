/// The fraction of events, or of groups of events, a ``Sampler`` keeps: a probability from 0, none,
/// to 1, every one.
///
/// A literal makes one, so a sampler reads as its rate:
///
/// ```swift
/// let sampler = Sampler.events(of: Scrolled.self, rate: 0.1)
/// ```
///
/// A kept record carries the rate it was kept at as its ``SampleRateKey``, so a destination can
/// count it as `1 / value` records.
public struct SampleRate: Hashable, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    /// The probability that a sampler keeps an event, or a group: 0 keeps none, 1 every one.
    public let value: Double

    /// The rate `value`.
    ///
    /// - Parameter value: The probability of keeping an event or a group.
    /// - Precondition: `value` is in 0 ... 1, so not NaN.
    public init(_ value: Double) {
        precondition((0 ... 1).contains(value), "A sample rate must be in 0 ... 1, not \(value)")
        self.value = value
    }

    /// The rate `checked`, throwing rather than trapping for one outside 0 ... 1.
    ///
    /// - Parameter checked: The probability of keeping an event or a group.
    /// - Throws: ``InvalidSampleRate`` when `checked` is below 0, above 1 or NaN.
    public init(checked: Double) throws(InvalidSampleRate) {
        guard (0 ... 1).contains(checked) else { throw InvalidSampleRate() }
        self.init(checked)
    }

    /// The rate a floating-point literal writes, such as `0.1`.
    ///
    /// - Parameter value: The probability of keeping an event or a group.
    /// - Precondition: `value` is in 0 ... 1.
    public init(floatLiteral value: Double) {
        self.init(value)
    }

    /// The rate an integer literal writes: `0`, none, or `1`, every one.
    ///
    /// - Parameter value: 0 or 1.
    /// - Precondition: `value` is 0 or 1.
    public init(integerLiteral value: Int) {
        self.init(Double(value))
    }
}
