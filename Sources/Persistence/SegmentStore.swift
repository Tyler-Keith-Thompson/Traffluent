public import Events
public import SystemPackage

/// A ``RecordStore`` that keeps records in a directory of append-only segment files, bounded in
/// size, until they are delivered.
///
/// ```swift
/// let store = try SegmentStore(events: [SignedUp.self, CheckedOut.self])
/// let tracker = Tracker(store: store)
/// let delivery = tracker.records.batch().deliver(to: vendor)
/// ```
///
/// - **Write-through.** A tracker's worker writes each record as it reaches it, before publishing
///   it, with one `write()`, off the tracking caller's thread, so the record survives the app
///   crashing or being killed from then on. The store makes the log durable against
///   power loss too (`fsync`) once per batch, before the batch is delivered, and whenever
///   ``synchronize()`` is called: call it, after the tracker's `flush()`, as the app moves to the
///   background or terminates.
///   A record whose write fails (the disk is full, say) is kept in memory only, and reported as
///   ``DropReport/writeFailed(recordCount:timestamps:)``.
/// - **What is kept.** Only events of the types in `events`, which conform to ``BinaryCodable``.
///   Events of any other type are kept in memory only: they are delivered in this run like any
///   other, are never written, and are lost if the app ends first. The first record of each such
///   type is reported as ``DropReport/notPersisted(event:)``, so a type left out of `events` by
///   mistake shows up.
///   A record's context is not kept: a recovered record is in the top-level `ServiceContext`,
///   as its span ended with the earlier run.
/// - **Deleting.** A segment is deleted as a whole once every record in it is delivered, so a
///   log whose records are all delivered holds no files. A segment kept for one undelivered
///   record keeps its delivered ones too. Only recovery rewrites a segment: one still holding
///   records after it drops some (``DropReport/undecodable(recordCount:)``,
///   ``DropReport/versionMismatch(event:storedVersion:currentVersion:recordCount:)``) is
///   rewritten without them, so each drop is reported once. Should the rewrite fail, the
///   segment is kept as it was and the next launch reports those drops again.
/// - **Reading back.** When a destination's full buffer drops a batch on its way through a
///   delivery, the delivery reads that batch's records back from the log once the destination
///   has caught up, reading each segment they are in once, and hands them to it in this run,
///   each in the context it was tracked in, which the delivery keeps. A record the bound dropped
///   before the read finished isn't read back, and one that can't be read or decoded is logged
///   and waits for a later launch.
/// - **Bound.** The log never holds more than `byteBound` bytes. When a record wouldn't fit, the
///   oldest segments are deleted until it does, and each one deleted with records not yet
///   delivered yields a ``DropReport`` on ``dropReports``. A record too large for an empty log
///   is kept in memory only.
/// - **Recovery.** A store opened on a directory recovers the records earlier runs left there
///   and a tracker given the store delivers them first. Each segment is cut at its first torn or
///   corrupt record, keeping every intact record before it, and the bytes cut off are reported.
///   A segment comes back whole, delivered records and all. Each record a delivery had started on
///   comes back with `isRedelivered` set, as it may have reached a destination already: one
///   delivered before the app ended, or one delivered just as it ended, before the store could
///   delete its segment. A record whose delivery mark can't be written is held back from that
///   delivery, so it is never sent twice unannounced, and delivered on a later launch.
/// - **Other versions.** A segment a newer release of the app wrote, in a later version of the
///   format, is left on disk untouched after a rollback, for that release to deliver: this one
///   neither reads it nor counts it toward the bound. A segment in an earlier version, which this
///   one can't read, is deleted and reported as a
///   ``DropReport/corruption(byteCount:)``.
/// - **Changed event types.** Each record's event is a map of its properties by name, so a record
///   written before its type changed still reads: a property removed since is skipped, an
///   optional one added since is `nil` and one with a default value added since has it. A record
///   stored at another `Event.schemaVersion` than its type's now is dropped without being read and
///   reported as ``DropReport/versionMismatch(event:storedVersion:currentVersion:recordCount:)``.
///   One at the same version that can't be read all the same, after a required property was added
///   or a property's type changed without raising the version, is dropped and reported as
///   ``DropReport/undecodable(recordCount:)``.
///
/// Open one store per directory at a time; two would delete each other's segments. Copies of a
/// store share its log.
public struct SegmentStore: RecordStore {
    /// The bound a store has unless it is given another: 5 MiB (5,242,880 bytes).
    public static let defaultByteBound = 5 * 1024 * 1024

    let log: SegmentLog

    /// A store keeping events of the types `events` in `directory`; it recovers the records
    /// already there.
    ///
    /// - Parameters:
    ///   - events: The event types to keep on disk. No two may share an `Event.name`.
    ///   - directory: Where the segment files go; created, with its parents, if missing.
    ///     ``defaultDirectory`` unless given.
    ///   - byteBound: The most bytes the log may hold.
    ///   - segmentByteCount: The size at which a segment is closed and a new one started; an
    ///     eighth of `byteBound` when `nil`.
    /// - Throws: ``SegmentStoreError/byteBoundTooSmall`` when `byteBound` is no more than 8
    ///   bytes (a segment's header), ``SegmentStoreError/nonPositiveSegmentByteCount`` when
    ///   `segmentByteCount` is given and isn't positive, ``SegmentStoreError/duplicateEventName``
    ///   when two of `events` share an `Event.name`, and ``SegmentStoreError/fileSystem(_:)`` when
    ///   the directory can't be created or read, or a segment in it can't be opened, read or
    ///   truncated.
    public init(
        events: [any (Event & BinaryCodable).Type],
        directory: FilePath = SegmentStore.defaultDirectory,
        byteBound: Int = SegmentStore.defaultByteBound,
        segmentByteCount: Int? = nil
    ) throws(SegmentStoreError) {
        guard byteBound > SegmentFormat.header.count else { throw .byteBoundTooSmall }
        guard segmentByteCount.map({ $0 > 0 }) ?? true else { throw .nonPositiveSegmentByteCount }
        let registry: EventRegistry
        do {
            registry = try EventRegistry(events)
        } catch {
            throw .duplicateEventName
        }
        do throws(Errno) {
            log = try SegmentLog(
                directory: directory,
                registry: registry,
                byteBound: byteBound,
                segmentByteCount: segmentByteCount ?? max(byteBound / 8, 1)
            )
        } catch {
            throw .fileSystem(error)
        }
    }

    /// Where the store keeps its segments.
    public var directory: FilePath {
        log.directory
    }

    /// A report of each drop, in the order they happen, from recovery onwards.
    ///
    /// Reports wait, without a bound, until they are read, so none is missed by reading late.
    /// Drops are rare (each is a whole segment, or bytes recovery couldn't read), so they don't
    /// pile up. The sequence has one consumer, and ends once the store is gone.
    public var dropReports: AsyncStream<DropReport> {
        log.dropReports
    }

    /// The bytes the log holds on disk: every segment's header, records and delivery marks.
    public var byteCount: Int {
        log.byteCount
    }

    /// How many records the log keeps that are not yet delivered.
    public var pendingRecordCount: Int {
        log.pendingRecordCount
    }

    /// Writes `record` to the log before returning, when its event type is one of `events` and
    /// it fits the bound.
    ///
    /// - Parameter record: The record just tracked.
    /// - Returns: `record` tagged with its position in the log, or as it was when it is kept in
    ///   memory only.
    public func append(_ record: EventRecord) -> EventRecord {
        log.append(record)
    }

    /// The records of the segments earlier runs left, oldest first, with `isRedelivered` set on
    /// each one a delivery had started on; later calls return none.
    public func takeRecoveredRecords() -> [EventRecord] {
        log.takeRecoveredRecords()
    }

    /// Flushes every segment written since the last flush to storage (`fsync`), so it survives
    /// power loss.
    public func synchronize() {
        log.synchronize()
    }
}
