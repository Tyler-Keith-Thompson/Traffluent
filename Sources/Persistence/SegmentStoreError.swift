public import SystemPackage

/// The error ``SegmentStore/init(events:directory:byteBound:segmentByteCount:)`` throws: an
/// argument it can't open a store with, or the file system's failure.
///
/// The cases for arguments carry nothing, and the file system's carries its `Errno`, so a single
/// `catch` handles every way opening a store fails.
public enum SegmentStoreError: Error, Sendable, Hashable {
    /// The bound is no more than 8 bytes, a segment's header, so no record could fit.
    case byteBoundTooSmall
    /// The segment size is zero or less.
    case nonPositiveSegmentByteCount
    /// Two of the event types share an `Event.name`, so recovery couldn't tell their records
    /// apart.
    case duplicateEventName
    /// The directory can't be created or read, or a segment in it can't be opened, read or
    /// truncated.
    case fileSystem(Errno)
}
