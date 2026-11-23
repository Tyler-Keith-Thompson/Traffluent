public import Events
public import Instrumentation
internal import SeedTrees

/// Keeps a fraction of the events it applies to, and drops the rest before they are held, written
/// or delivered: event by event, or a whole group of events, such as a session, at once.
///
/// A tracker built with samplers runs them on its worker, after its enrichers, so a sampler sees
/// what they set:
///
/// ```swift
/// let tracker = Tracker(samplers: [
///     .events(of: Scrolled.self, rate: 0.1),
///     .events(where: { $0.consentCategory == .performance }, rate: 0.5),
/// ])
/// ```
///
/// Each sampler decides on its own, and a record is kept only if every sampler that applies to it
/// keeps it. A kept record carries the product of their rates as its ``SampleRateKey``; one no
/// sampler applies to is always kept and carries no key. Each dropped record is reported on
/// ``Tracker/samplingDropReports``.
///
/// The decisions come from the tracker's sampling seed, the same on every platform and Swift
/// release: with a seed fixed, which events are kept is fixed too. Each sampler draws from a
/// stream of its own, picked by its place in the tracker's list: appending a sampler changes no
/// other's decisions, but inserting, removing or reordering one gives every sampler after it a new
/// stream, so it decides differently under the same seed.
public struct Sampler: Sendable {
    /// The probability that the sampler keeps an event, or a group, it applies to.
    let rate: SampleRate
    let selects: @Sendable (EventRecord) -> Bool
    /// How a group's decision is made, for a sampler of groups; `nil` for one deciding each event.
    let grouping: (@Sendable (SeedTree, SampleRate) -> any GroupDecision)?

    /// A sampler that keeps each event of type `type` with probability `rate`, deciding each on
    /// its own.
    ///
    /// - Parameters:
    ///   - type: The type of event to sample.
    ///   - rate: The fraction of them to keep.
    /// - Returns: The sampler.
    public static func events<E: Event>(of type: E.Type, rate: SampleRate) -> Sampler {
        Sampler(rate: rate, selects: { $0.event is E }, grouping: nil)
    }

    /// A sampler that keeps each record `selects` returns `true` for with probability `rate`,
    /// deciding each on its own.
    ///
    /// - Parameters:
    ///   - selects: Whether the sampler applies to a record. It runs on the tracker's worker, on
    ///     each enriched record, so it sees the record's event and its context.
    ///   - rate: The fraction of the records it applies to to keep.
    /// - Returns: The sampler.
    public static func events(where selects: @escaping @Sendable (EventRecord) -> Bool, rate: SampleRate) -> Sampler {
        Sampler(rate: rate, selects: selects, grouping: nil)
    }

    /// A sampler that keeps or drops whole groups of records, those whose contexts hold one value
    /// of `key`, keeping each group with probability `rate`.
    ///
    /// Every record of a group gets the same decision, made from the tracker's sampling seed and
    /// the value's `description`, so values with equal descriptions make one group. Use a key whose
    /// value describes itself stably and consistently with `==`, such as a `String` or a `UUID`: a
    /// type described by reflection changes group, and so decision, when its fields change. Nothing is
    /// remembered: the decision is made again for each group, from the seed alone, and a sampler
    /// keeps only the latest group's to skip making it again for the next record of that group.
    /// A record whose context holds no value of `key` belongs to no group, so the sampler doesn't
    /// apply to it.
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [experiment], samplers: [.grouped(by: ExperimentKey.self, rate: 0.5)])
    /// ```
    ///
    /// - Parameters:
    ///   - key: The context key whose value names a record's group.
    ///   - selects: Whether the sampler applies to a record; every record by default.
    ///   - rate: The fraction of the groups to keep.
    /// - Returns: The sampler.
    public static func grouped<Key: ServiceContextKey>(
        by key: Key.Type,
        where selects: @escaping @Sendable (EventRecord) -> Bool = { _ in true },
        rate: SampleRate
    ) -> Sampler where Key.Value: Hashable & CustomStringConvertible {
        Sampler(rate: rate, selects: selects, grouping: { node, rate in KeyedGroupDecision<Key>(node: node, rate: rate) })
    }
}

/// How a sampler of groups decides whether the group a record belongs to is kept.
protocol GroupDecision {
    /// Whether the group `record` belongs to is kept; `nil` when it belongs to none.
    mutating func keeps(_ record: EventRecord) -> Bool?
}

/// The groups the values of `Key` make, each decided by the seed tree node of its value's
/// description.
struct KeyedGroupDecision<Key: ServiceContextKey>: GroupDecision where Key.Value: Hashable & CustomStringConvertible {
    /// A group's decision.
    struct Decided {
        let group: Key.Value
        let keeps: Bool
    }

    let node: SeedTree
    let rate: SampleRate
    // The latest group's decision only, so the memory stays one group's however many there are:
    // records of one group, such as a session's, come together, and a group seen again is
    // decided again, the same way, from its node.
    private var latest: Decided?

    init(node: SeedTree, rate: SampleRate) {
        self.node = node
        self.rate = rate
    }

    mutating func keeps(_ record: EventRecord) -> Bool? {
        guard let group = record.context[Key.self] else { return nil }
        if let latest, latest.group == group {
            return latest.keeps
        }
        // A node per group, keyed by the value's description rather than its hash value, which
        // changes from one process to the next: the decision is the node's first draw, the same
        // in every run with the seed.
        let keeps = node[group.description].bernoulli(rate.value)
        latest = Decided(group: group, keeps: keeps)
        return keeps
    }
}
