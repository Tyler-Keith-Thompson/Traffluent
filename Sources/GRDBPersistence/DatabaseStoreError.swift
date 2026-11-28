#if canImport(GRDB)
public import GRDB

/// The error ``DatabaseStore/init(events:database:table:byteBound:)`` throws: an argument it
/// can't open a store with, or the database's failure.
///
/// The cases for arguments carry nothing but the clashing event names, and the database's carries
/// its `DatabaseError`, so a single `catch` handles every way opening a store fails.
// Not Hashable, unlike SegmentStoreError: GRDB's DatabaseError isn't Equatable, so the case that
// carries it can't be compared. A caller matches the case with `catch` or `if case` instead.
public enum DatabaseStoreError: Error, Sendable {
    /// The bound is zero or less.
    case nonPositiveByteBound
    /// Two of the event types share an `Event.name`, so recovery couldn't tell their records
    /// apart: two of the listed `events`, whatever their versions, or two of the discovered events
    /// that share a version too. It holds the name, and the fully qualified names
    /// (`String(reflecting:)`) of the type that came first and the one that came second. Rename
    /// one of them, or leave one out of the list.
    case duplicateEventName(String, firstType: String, secondType: String)
    /// The table can't be created (the database is read-only, or the table's name holds a double
    /// quote) or read, or the rows recovery drops can't be deleted.
    case database(DatabaseError)
}
#endif
