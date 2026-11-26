public import Events
import Logging

extension Destination {
    /// This destination, receiving each record with its context changed by `enricher`.
    ///
    /// ```swift
    /// let delivery = tracker.records.batch().deliver(
    ///     to: ownBackend.enriched(by: Enricher { $0[RegionKey.self] = "eu-west" }),
    ///     vendor
    /// )
    /// ```
    ///
    /// The enricher runs on each record of a batch as the delivery hands the batch to this
    /// destination, not on the tracker's worker, so what it sets reaches this destination alone:
    /// the others are handed the same records without it. It runs on every record the destination
    /// receives, records a store recovered from an earlier run included, and reads any value it
    /// computes at delivery rather than when the event was tracked. So it suits values about the
    /// destination or the delivery, such as a region or a deployment tag, rather than about the
    /// event: a recovered record would get this run's app version and the network at upload time.
    ///
    /// Like the other modifiers, the one applied last sees each record first: in
    /// `destination.enriched(by: first).enriched(by: second)`, `second` runs, then `first`, which
    /// sees what `second` set and has the last word on a key both set.
    ///
    /// Records the enricher adds before a record, as `Enricher.sessions()` adds `SessionStarted`
    /// and `SessionEnded`, are left out: they would reach the destination without passing the
    /// tracker's consent, samplers or store. Given such an enricher, this logs a warning once, as
    /// it is called. Give that kind of enricher to the tracker instead.
    ///
    /// - Parameter enricher: What each record this destination receives adds to its context.
    /// - Returns: A destination that hands this one each batch with its records enriched.
    /// - Complexity: O(*n*) enricher calls for a batch of *n* records.
    public func enriched(by enricher: Enricher) -> some Destination {
        if enricher.addsRecords {
            // A warning rather than a thrown error: the destination still gets every record,
            // enriched, and only the added ones are missing, which a log says once.
            EnrichedLog.logger.warning("enriched(by:) was given an enricher that adds records, such as Enricher.sessions(); the records it adds are left out at a destination. Give it to the tracker instead")
        }
        return TransformingDestination(base: self) { record in
            var record = record
            // The records it would add are dropped, as the doc comment says: past the tracker's
            // worker there is no consent gate, sampler or store for them to pass through.
            _ = enricher(&record)
            return record
        }
    }
}

/// The log of `Destination.enriched(by:)`: a static stored property can't live in a protocol
/// extension.
private enum EnrichedLog {
    static let logger = Logger(label: "Destinations.Enriched")
}
