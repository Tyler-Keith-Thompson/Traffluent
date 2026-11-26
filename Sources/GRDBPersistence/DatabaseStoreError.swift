#if canImport(GRDB)
public import GRDB

/// The error ``DatabaseStore/init(events:database:table:byteBound:)`` throws: an argument it
/// can't open a store with, or the database's failure.
///
/// The cases for arguments carry nothing, and the database's carries its `DatabaseError`, so a
/// single `catch` handles every way opening a store fails.
// Not Hashable, unlike SegmentStoreError: GRDB's DatabaseError isn't Equatable, so the case that
// carries it can't be compared. A caller matches the case with `catch` or `if case` instead.
public enum DatabaseStoreError: Error, Sendable {
    /// The bound is zero or less.
    case nonPositiveByteBound
    /// Two of the event types share an `Event.name`, so recovery couldn't tell their records
    /// apart.
    case duplicateEventName
    /// The table can't be created (the database is read-only, or the table's name holds a double
    /// quote) or read, or the rows recovery drops can't be deleted.
    case database(DatabaseError)
}
#endif
