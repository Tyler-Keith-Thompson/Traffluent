public import Events

/// Where a tracker keeps each record until it is delivered, so records survive the app ending.
///
/// A tracker given a store (`Tracker(store:)`) appends each record to it as the tracker's worker
/// reaches the record, before publishing it, and starts its records with the ones the store kept
/// from earlier runs. A store tags each record
/// it keeps with a `DeliveryTag` naming itself as the `Acknowledger`, so a
/// delivery tells it when the record is about to be delivered and once it has been.
/// ``SegmentStore`` is the default; conform to keep records elsewhere.
public protocol RecordStore: Sendable {
    /// Keeps `record` until it is delivered.
    ///
    /// Called on the tracker's worker, never on the tracking caller's thread, one record at a
    /// time in the order tracked: a slow write delays the records after it, not `track`.
    ///
    /// - Parameter record: The record just tracked.
    /// - Returns: `record` with its `EventRecord.deliveryTag` set, or `record` as it was
    ///   when the store doesn't keep it (its event type has no encoding, say), and it is then
    ///   kept in memory only.
    func append(_ record: EventRecord) -> EventRecord

    /// The records kept from earlier runs, oldest first; each later call returns none, so only
    /// one tracker starts with them.
    ///
    /// A store may return records that were delivered but not yet forgotten, as a
    /// ``SegmentStore`` does for a segment not wholly delivered; it marks them redelivered.
    ///
    /// - Returns: The records, tagged, with `EventRecord.isRedelivered` set on each one a
    ///   delivery had started on.
    func takeRecoveredRecords() -> [EventRecord]

    /// Makes every record appended so far durable against power loss, not only against the app
    /// ending. Call it as the app moves to the background or terminates.
    func synchronize()
}
