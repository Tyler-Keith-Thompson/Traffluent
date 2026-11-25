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
    /// the store's `events`, or its ``BinaryCodable/init(from:)`` threw, as it does for a record
    /// written before a required property was added or a property's type changed while the
    /// event's `Event.schemaVersion` stayed the same.
    case undecodable(recordCount: Int)
    /// Recovery read `recordCount` intact records of the event named `event` stored at
    /// `storedVersion`, while the store's type of that name is at `currentVersion`
    /// (`Event.schemaVersion`), and dropped them without decoding them: the version changed for a
    /// change their bytes can't be read through. Reported once per segment, or per database, for
    /// each event and stored version, by the event's name and then the stored version.
    case versionMismatch(event: String, storedVersion: Int, currentVersion: Int, recordCount: Int)
    /// A record of the event named `event` was kept in memory only because its type isn't one of
    /// the store's `events`: its records are delivered in this run, but never written, so they are
    /// lost if the app ends first. Reported once per type, on its first record, for as long as the
    /// store lives; a type left out by mistake is added to `events`.
    case notPersisted(event: String)
    /// Recovery found a torn or corrupt record, or a segment header it couldn't read, and
    /// discarded the `byteCount` bytes from there to the end of the segment.
    case corruption(byteCount: Int)
}
