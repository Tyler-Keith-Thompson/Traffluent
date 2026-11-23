public import Instrumentation

/// The `ServiceContext` key of the rate a record was kept at, which a tracker's ``Sampler``s set on
/// the context of every record they keep.
///
/// A destination weights each record by it, counting one kept at 0.1 as ten:
///
/// ```swift
/// let weight = 1 / (record.context[SampleRateKey.self]?.value ?? 1)
/// ```
///
/// A record that several samplers kept carries the product of their rates, the probability that
/// it was kept. One no sampler applies to carries no key: it was kept for certain. Nor does one a
/// store recovered from an earlier run, which comes back in the top-level context.
public enum SampleRateKey: ServiceContextKey {
    /// The rate the record was kept at.
    public typealias Value = SampleRate
}
