public import SystemPackage

/// The error ``SegmentStore/init(events:directory:byteBound:segmentByteCount:)`` throws: an
/// argument it can't open a store with, or the file system's failure.
///
/// The cases for arguments carry nothing but the clashing event names, and the file system's
/// carries its `Errno`, so a single `catch` handles every way opening a store fails.
public enum SegmentStoreError: Error, Sendable, Hashable {
    /// The bound is no more than 8 bytes, a segment's header, so no record could fit.
    case byteBoundTooSmall
    /// The segment size is zero or less.
    case nonPositiveSegmentByteCount
    /// Two of the event types share an `Event.name`, so recovery couldn't tell their records
    /// apart: two of the listed `events`, whatever their versions, or two of the discovered events
    /// that share a version too. It holds the name, and the fully qualified names
    /// (`String(reflecting:)`) of the type that came first and the one that came second. Rename
    /// one of them, or leave one out of the list.
    case duplicateEventName(String, firstType: String, secondType: String)
    /// The directory can't be created or read, or a segment in it can't be opened, read or
    /// truncated.
    case fileSystem(Errno)
}
