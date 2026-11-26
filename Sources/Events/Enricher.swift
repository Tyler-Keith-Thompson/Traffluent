public import Instrumentation

/// Adds to the context of each event a tracker tracks, before the record is delivered.
///
/// An enricher reads and sets values through typed `ServiceContextKey`s, so what it adds keeps its
/// type all the way to the destinations:
///
/// ```swift
/// enum ExperimentKey: ServiceContextKey {
///     typealias Value = String
/// }
///
/// let experiment = Enricher { context in
///     context[ExperimentKey.self] = "new-checkout"
/// }
/// let tracker = Tracker(enrichers: [experiment])
/// ```
///
/// A tracker's worker runs its enrichers in order, on the context `track` took from
/// `ServiceContext.current` when the event was tracked: an enricher sees what earlier ones set,
/// and may override a value the caller's context already holds. It runs on the worker, not the
/// tracking caller's thread, so it sees the caller's context only, not its other task-local
/// values or its actor.
///
/// Given to one destination instead, with `enriched(by:)` (module `Destinations`), an enricher
/// runs on the records that destination receives as the delivery hands it each batch, so the
/// tracker's other destinations don't see what it sets.
// In Events rather than Trackers, beside `EventRecord`, because both a tracker and a destination
// modifier run it, and Destinations doesn't depend on Trackers.
public struct Enricher: Sendable {
    // The whole record, and records to add before it, rather than the context alone: an enricher
    // of the library's own (`Enricher.sessions`, module Sessions) reads the record's timestamp and
    // adds the events that mark a session's end and start. A public enricher sets the context only.
    private let enrich: @Sendable (inout EventRecord) -> [EventRecord]

    /// Whether this enricher can add records before the one it enriches: made with
    /// `init(records:)`, as `Enricher.sessions` is.
    ///
    /// Package-wide, so a destination modifier, which leaves such records out, can say so.
    package let addsRecords: Bool

    /// An enricher that changes each record's context with `enrich`.
    ///
    /// - Parameter enrich: Sets the values it adds on the context it is given. Given to a
    ///   tracker, it runs on the tracker's worker for every event, in order, so a slow one delays
    ///   every record after it. Given to a destination with `enriched(by:)`, it runs in that
    ///   destination's delivery, so a slow one delays only that destination's batches.
    public init(_ enrich: @escaping @Sendable (inout ServiceContext) -> Void) {
        self.enrich = { record in
            enrich(&record.context)
            return []
        }
        addsRecords = false
    }

    /// An enricher that changes each record with `enrich`, and adds the records it returns before
    /// that record.
    ///
    /// The tracker's worker runs the enrichers after this one on each added record, in order, as
    /// on a tracked one, and delivers the added records first, in the order returned.
    ///
    /// - Parameter enrich: Changes the record it is given and returns the records to add before
    ///   it; none, usually.
    package init(records enrich: @escaping @Sendable (inout EventRecord) -> [EventRecord]) {
        self.enrich = enrich
        addsRecords = true
    }

    /// Changes `record` as this enricher does.
    ///
    /// - Parameter record: The record to enrich.
    /// - Returns: The records this enricher adds before `record`.
    package func callAsFunction(_ record: inout EventRecord) -> [EventRecord] {
        enrich(&record)
    }
}
