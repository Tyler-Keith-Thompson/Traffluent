public import Foundation

/// Records a store dropped before they were delivered, and why.
///
/// A ``SegmentStore`` reports every drop on its ``SegmentStore/dropReports``. A dropped record is
/// no longer kept on disk: if the app ends before it is delivered, it is lost. A record already in
/// memory, read by a delivery or held by a consent, may still be delivered in this run.
public enum DropReport: Sendable, Hashable {
    /// The log reached its byte bound, so its oldest segment was deleted with `recordCount`
    /// records not yet delivered, tracked within `timestamps`.
    case sizeBound(recordCount: Int, timestamps: ClosedRange<Date>)
    /// Writing `recordCount` records, tracked within `timestamps`, to disk failed (the disk is
    /// full, say, or segments that couldn't be deleted fill the bound), so they are kept in memory
    /// only: delivered in this run if it lasts long
    /// enough, lost if it ends first.
    case writeFailed(recordCount: Int, timestamps: ClosedRange<Date>)
    /// Recovery read `recordCount` intact records it couldn't decode: their event type isn't in
    /// the store's `events`, or its ``BinaryCodable/init(from:)`` threw.
    case undecodable(recordCount: Int)
    /// Recovery found a torn or corrupt record, or a segment header it couldn't read, and
    /// discarded the `byteCount` bytes from there to the end of the segment.
    case corruption(byteCount: Int)
}
