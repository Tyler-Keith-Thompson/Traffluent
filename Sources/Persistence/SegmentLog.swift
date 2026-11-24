public import Events
import Foundation
import Logging
import Synchronization
import SystemPackage

/// The segment files of a ``SegmentStore``, and what is known about each.
///
/// Segments are numbered in the order they were created, and the files are named by number, so
/// the oldest comes first in a listing. Appends go to the active segment, created in this run;
/// segments recovered from earlier runs only gain delivery marks and are deleted once delivered.
final class SegmentLog: Acknowledger {
    /// One segment file and the state of its records.
    struct Segment {
        let number: UInt64
        let file: SegmentFile
        var byteCount: Int
        /// When each record, by number, was tracked; for drop reports.
        var timestamps: [Date]
        /// Whether each record, by number, has been acknowledged.
        var acknowledged: [Bool]
        /// How many records are not yet acknowledged.
        var pendingCount: Int
        /// Whether bytes were written since the last synchronization.
        var needsSynchronization: Bool
    }

    /// A record recovered from an earlier run, and its position in the log.
    struct Recovered {
        let record: EventRecord
        let position: UInt64
    }

    struct State {
        /// Oldest first; the last is the active one when `hasActive` is true.
        var segments: [Segment]
        var hasActive = false
        var nextNumber: UInt64
        var byteCount: Int
        var recovered: [Recovered]
        /// Whether a segment was created since the directory was last synchronized.
        var directoryNeedsSynchronization = false
        /// The numbers of segments taken out of the log whose files couldn't be deleted: their
        /// records come back on the next launch, so they must not be delivered unmarked.
        var undeleted: Set<UInt64> = []
    }

    /// What `append` did with a record's frame.
    private enum Appending {
        /// Written, at this position.
        case written(UInt64)
        /// Not written: the frame is larger than an empty log can hold.
        case tooLarge
        /// Not written: creating a segment or writing to one failed.
        case failed(Errno)
        /// Not written: segment files that couldn't be deleted leave no room within the bound.
        case full
    }

    /// Whether the active segment can take a frame.
    private enum Room {
        case ready
        /// The frame is larger than an empty log can hold.
        case tooLarge
        /// A new segment was needed and couldn't be created.
        case failed(Errno)
        /// Segment files that couldn't be deleted leave no room within the bound.
        case full
    }

    /// The files, and whether the directory, to flush to storage.
    private struct PendingSynchronization {
        var files: [SegmentFile] = []
        var directory = false
    }

    let directory: FilePath
    private let registry: EventRegistry
    private let byteBound: Int
    private let segmentByteCount: Int
    // A Mutex rather than an actor: `append` is synchronous, as `RecordStore` declares it, so it
    // can't await an actor. Every section is short (a write() of one record, or a few file deletions);
    // fsync, the one slow call, runs outside it.
    private let state: Mutex<State>
    let dropReports: AsyncStream<DropReport>
    private let dropReporter: AsyncStream<DropReport>.Continuation

    private static let logger = Logger(label: "Persistence.SegmentStore")

    /// A segment file's name: its number in 20 decimal digits, so names sort as numbers do.
    static func fileName(of number: UInt64) -> String {
        let digits = String(number)
        return String(repeating: "0", count: 20 - digits.count) + digits + ".segment"
    }

    /// The number a segment file's name holds, or `nil` for any other file.
    static func number(inFileName name: String) -> UInt64? {
        guard name.hasSuffix(".segment") else { return nil }
        let digits = name.dropLast(".segment".count)
        guard digits.count == 20, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return UInt64(digits)
    }

    /// The log in `directory`, recovered from the segments there.
    init(directory: FilePath, registry: EventRegistry, byteBound: Int, segmentByteCount: Int) throws(Errno) {
        self.directory = directory
        self.registry = registry
        self.byteBound = byteBound
        self.segmentByteCount = segmentByteCount
        (dropReports, dropReporter) = AsyncStream.makeStream(of: DropReport.self)
        try directory.createDirectory()
        var reports: [DropReport] = []
        var recovered = try Self.recover(directory: directory, registry: registry, reports: &reports)
        while recovered.state.byteCount > byteBound, !recovered.state.segments.isEmpty {
            let evicted = recovered.state.segments.removeFirst()
            recovered.records.removeFirst()
            Self.delete(evicted, from: &recovered.state, reports: &reports)
        }
        var state = recovered.state
        state.recovered = recovered.records.flatMap { $0 }
        self.state = Mutex(state)
        for report in reports {
            dropReporter.yield(report)
        }
    }

    deinit {
        dropReporter.finish()
    }

    // MARK: Appending

    /// Appends `record`'s frame, or returns `record` as it was when its event type isn't
    /// persisted, it can't fit in the bound, or the write fails; a failed write is reported.
    func append(_ record: EventRecord) -> EventRecord {
        guard let registration = registry.registration(of: type(of: record.event)) else { return record }
        let frame = SegmentFormat.recordFrame(of: record, registration: registration)
        let appending: Appending = state.withLock { state in
            switch makeRoom(for: frame.count, in: &state) {
            case .ready: break
            case .tooLarge: return .tooLarge
            case .failed(let error): return .failed(error)
            case .full: return .full
            }
            let active = state.segments.count - 1
            do throws(Errno) {
                try withErrno { try state.segments[active].file.descriptor.writeAll(frame) }
            } catch {
                // Cut off whatever part of the frame reached the file, and start the next record
                // in a new segment; if the cut fails too, recovery truncates the torn frame.
                try? state.segments[active].file.descriptor.resize(to: Int64(state.segments[active].byteCount))
                state.hasActive = false
                return .failed(error)
            }
            let index = UInt64(state.segments[active].timestamps.count)
            state.segments[active].byteCount += frame.count
            state.segments[active].timestamps.append(record.timestamp)
            state.segments[active].acknowledged.append(false)
            state.segments[active].pendingCount += 1
            state.segments[active].needsSynchronization = true
            state.byteCount += frame.count
            return .written(state.segments[active].number << 32 | index)
        }
        let position: UInt64
        switch appending {
        case .written(let written):
            position = written
        case .tooLarge:
            Self.logger.notice("Kept a \(registration.name) record in memory only: its \(frame.count) bytes are more than a log bounded to \(byteBound) bytes can hold")
            return record
        case .failed(let error):
            Self.logger.error("Kept a \(registration.name) record in memory only: writing it to \(directory) failed with \(error)")
            dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))
            return record
        case .full:
            Self.logger.error("Kept a \(registration.name) record in memory only: segments in \(directory) that couldn't be deleted fill its bound of \(byteBound) bytes")
            dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))
            return record
        }
        var tagged = record
        tagged.deliveryTag = DeliveryTag(acknowledger: self, position: position)
        return tagged
    }

    /// Makes the active segment able to take `frameByteCount` more bytes within the bound:
    /// starts a new segment when the active one is full, and deletes the oldest segments while
    /// the log would pass its bound.
    ///
    /// - Returns: `.tooLarge`, changing nothing, when the frame can't fit even in an empty log;
    ///   `.full` when segments that couldn't be deleted leave no room; `.failed` when a new
    ///   segment can't be created.
    private func makeRoom(for frameByteCount: Int, in state: inout State) -> Room {
        guard frameByteCount <= byteBound - SegmentFormat.header.count else { return .tooLarge }
        if state.hasActive, let active = state.segments.last,
            active.byteCount + frameByteCount > segmentByteCount || UInt64(active.timestamps.count) == UInt64(UInt32.max)
        {
            state.hasActive = false
        }
        while state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) > byteBound, !state.segments.isEmpty {
            // When only the active segment is left, it is the oldest: it goes too, and the frame
            // starts a new one.
            state.hasActive = state.hasActive && state.segments.count > 1
            var reports: [DropReport] = []
            Self.delete(state.segments.removeFirst(), from: &state, reports: &reports)
            for report in reports {
                dropReporter.yield(report)
            }
        }
        // Segments whose files couldn't be deleted still take their bytes on disk.
        guard state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) <= byteBound else { return .full }
        if !state.hasActive {
            do throws(Errno) {
                try startSegment(in: &state)
            } catch {
                return .failed(error)
            }
        }
        return .ready
    }

    /// Creates the next segment, with its header, as the active one.
    private func startSegment(in state: inout State) throws(Errno) {
        let number = state.nextNumber
        // A position is the segment's number above 32 bits of record number; a directory would
        // need four billion segments for this to fire.
        precondition(number < 1 << 32, "The log in \(directory) has used every segment number")
        let path = directory.appending(Self.fileName(of: number))
        let descriptor = try withErrno {
            try FileDescriptor.open(path, .writeOnly, options: [.create, .exclusiveCreate, .append], permissions: [.ownerReadWrite])
        }
        let file = SegmentFile(path: path, descriptor: descriptor)
        do throws(Errno) {
            try withErrno { try descriptor.writeAll(SegmentFormat.header) }
        } catch {
            try? path.removeFile()
            throw error
        }
        state.nextNumber += 1
        state.segments.append(Segment(number: number, file: file, byteCount: SegmentFormat.header.count, timestamps: [], acknowledged: [], pendingCount: 0, needsSynchronization: true))
        state.hasActive = true
        state.byteCount += SegmentFormat.header.count
        state.directoryNeedsSynchronization = true
    }

    /// Deletes `segment`'s file, already removed from `state.segments`, reporting its records
    /// not yet acknowledged as dropped.
    private static func delete(_ segment: Segment, from state: inout State, reports: inout [DropReport]) {
        do throws(Errno) {
            try segment.file.path.removeFile()
            // Only once the file is gone: one that stays still takes its bytes on disk.
            state.byteCount -= segment.byteCount
        } catch {
            state.undeleted.insert(segment.number)
            logger.error("Couldn't delete the segment \(segment.file.path): \(error)")
        }
        let pending = zip(segment.timestamps, segment.acknowledged).filter { !$0.1 }.map(\.0)
        if let earliest = pending.min(), let latest = pending.max() {
            reports.append(.sizeBound(recordCount: pending.count, timestamps: earliest...latest))
        }
    }

    // MARK: Delivery

    /// Writes a delivery mark for the records at `positions`, returning those it couldn't mark.
    ///
    /// A record whose mark failed is withheld from this delivery rather than delivered unmarked:
    /// after a crash it would come back without `isRedelivered`, sent twice unannounced. It stays
    /// on disk, unacknowledged, and is delivered on a later launch. Dropping it instead (reported,
    /// and forgotten in memory) wouldn't help: its unmarked frame stays on disk, and recovery
    /// would resend it all the same.
    func willDeliver(_ positions: [UInt64]) -> Set<UInt64> {
        var withheld: Set<UInt64> = []
        let pending: PendingSynchronization = state.withLock { state in
            for (number, indices) in Self.indicesBySegment(positions) {
                let frame = SegmentFormat.deliveryMarkFrame(of: indices)
                while state.byteCount + frame.count > byteBound, !state.segments.isEmpty {
                    state.hasActive = state.hasActive && state.segments.count > 1
                    var reports: [DropReport] = []
                    Self.delete(state.segments.removeFirst(), from: &state, reports: &reports)
                    for report in reports {
                        dropReporter.yield(report)
                    }
                }
                guard let segment = state.segments.firstIndex(where: { $0.number == number }) else {
                    // A deleted segment's records are on disk no more, so they can go unmarked;
                    // one whose file is still there would bring them back unmarked.
                    if state.undeleted.contains(number) {
                        withheld.formUnion(indices.map { number << 32 | UInt64($0) })
                    }
                    continue
                }
                do throws(Errno) {
                    try withErrno { try state.segments[segment].file.descriptor.writeAll(frame) }
                } catch {
                    try? state.segments[segment].file.descriptor.resize(to: Int64(state.segments[segment].byteCount))
                    Self.logger.error("Held \(indices.count) records in \(state.segments[segment].file.path) back from delivery until a later launch: marking them as being delivered failed with \(error)")
                    withheld.formUnion(indices.map { number << 32 | UInt64($0) })
                    continue
                }
                state.segments[segment].byteCount += frame.count
                state.segments[segment].needsSynchronization = true
                state.byteCount += frame.count
            }
            return Self.pendingSynchronization(in: &state)
        }
        // Once per batch, before it is delivered, so the records and their mark are durable. This
        // runs on the delivery's task by design: the batch must not reach a destination before
        // its mark is on storage, so there is nothing to gain by moving the wait elsewhere.
        synchronize(pending)
        return withheld
    }

    func acknowledge(_ positions: [UInt64]) {
        state.withLock { state in
            var finished: Set<UInt64> = []
            for (number, indices) in Self.indicesBySegment(positions) {
                guard let segment = state.segments.firstIndex(where: { $0.number == number }) else { continue }
                for index in indices.map(Int.init) where index < state.segments[segment].acknowledged.count {
                    guard !state.segments[segment].acknowledged[index] else { continue }
                    state.segments[segment].acknowledged[index] = true
                    state.segments[segment].pendingCount -= 1
                }
                if state.segments[segment].pendingCount == 0 {
                    finished.insert(number)
                }
            }
            guard !finished.isEmpty else { return }
            if state.hasActive, let active = state.segments.last, finished.contains(active.number) {
                state.hasActive = false
            }
            var reports: [DropReport] = []
            let (done, kept) = (state.segments.filter { finished.contains($0.number) }, state.segments.filter { !finished.contains($0.number) })
            state.segments = kept
            for segment in done {
                Self.delete(segment, from: &state, reports: &reports)
            }
        }
    }

    /// `positions` as record numbers grouped by segment, segments in order of first appearance.
    private static func indicesBySegment(_ positions: [UInt64]) -> [(UInt64, [UInt32])] {
        var groups: [(UInt64, [UInt32])] = []
        for position in positions {
            let number = position >> 32
            let index = UInt32(truncatingIfNeeded: position)
            if let last = groups.indices.last, groups[last].0 == number {
                groups[last].1.append(index)
            } else if let group = groups.firstIndex(where: { $0.0 == number }) {
                groups[group].1.append(index)
            } else {
                groups.append((number, [index]))
            }
        }
        return groups
    }

    // MARK: Synchronizing

    /// Synchronizes every segment written since its last synchronization.
    func synchronize() {
        synchronize(state.withLock { Self.pendingSynchronization(in: &$0) })
    }

    private static func pendingSynchronization(in state: inout State) -> PendingSynchronization {
        var pending = PendingSynchronization()
        for segment in state.segments.indices where state.segments[segment].needsSynchronization {
            state.segments[segment].needsSynchronization = false
            pending.files.append(state.segments[segment].file)
        }
        pending.directory = state.directoryNeedsSynchronization
        state.directoryNeedsSynchronization = false
        return pending
    }

    private func synchronize(_ pending: PendingSynchronization) {
        for file in pending.files {
            do throws(Errno) {
                try file.descriptor.synchronize()
            } catch {
                Self.logger.error("Couldn't synchronize the segment \(file.path): \(error)")
            }
        }
        guard pending.directory else { return }
        do throws(Errno) {
            try directory.synchronizeDirectory()
        } catch {
            Self.logger.error("Couldn't synchronize the directory \(directory): \(error)")
        }
    }

    // MARK: Reading

    /// The records recovered from earlier runs, tagged; later calls return none.
    func takeRecoveredRecords() -> [EventRecord] {
        let recovered = state.withLock { state in
            let recovered = state.recovered
            state.recovered = []
            return recovered
        }
        return recovered.map { recovered in
            var record = recovered.record
            record.deliveryTag = DeliveryTag(acknowledger: self, position: recovered.position)
            return record
        }
    }

    /// The bytes the log holds on disk.
    var byteCount: Int {
        state.withLock { $0.byteCount }
    }

    /// The records kept that are not yet acknowledged.
    var pendingRecordCount: Int {
        state.withLock { $0.segments.reduce(0) { $0 + $1.pendingCount } }
    }

    // MARK: Recovering

    /// The segments in `directory` and the records each holds, each segment cut at its first
    /// torn or corrupt frame; segments with nothing left to deliver are deleted.
    private static func recover(
        directory: FilePath,
        registry: EventRegistry,
        reports: inout [DropReport]
    ) throws(Errno) -> (state: State, records: [[Recovered]]) {
        let numbers = try directory.directoryEntries().compactMap(number(inFileName:)).sorted()
        var state = State(segments: [], nextNumber: (numbers.last ?? 0) + 1, byteCount: 0, recovered: [])
        var records: [[Recovered]] = []
        for number in numbers {
            let path = directory.appending(fileName(of: number))
            let descriptor = try withErrno { try FileDescriptor.open(path, .readWrite, options: [.append]) }
            let file = SegmentFile(path: path, descriptor: descriptor)
            let bytes = try descriptor.readAll()
            let contents: SegmentFormat.Contents
            switch SegmentFormat.read(bytes) {
            case .segment(let read):
                contents = read
            case .newerVersion(let version):
                // A newer release wrote it, and this one was rolled back to: leave it for that
                // release to deliver when it returns. It isn't this log's, so it doesn't count
                // toward the bound.
                logger.notice("Left the segment \(path) alone: it is in version \(version) of the format, newer than this release's \(SegmentFormat.version)")
                continue
            case .unreadable:
                if !bytes.isEmpty {
                    reports.append(.corruption(byteCount: bytes.count))
                }
                try path.removeFile()
                continue
            }
            if contents.validByteCount < bytes.count {
                try withErrno { try descriptor.resize(to: Int64(contents.validByteCount)) }
                reports.append(.corruption(byteCount: bytes.count - contents.validByteCount))
            }
            var segment = Segment(number: number, file: file, byteCount: contents.validByteCount, timestamps: [], acknowledged: [], pendingCount: 0, needsSynchronization: false)
            var segmentRecords: [Recovered] = []
            var undecodable = 0
            var mismatches = VersionMismatchCounts()
            for frame in contents.records {
                do throws(BinaryDecodingError) {
                    switch try RecordEncoding.record(from: bytes[frame.payload], registry: registry) {
                    case .record(var record):
                        record.isRedelivered = contents.marked.contains(frame.index)
                        segment.timestamps.append(record.timestamp)
                        segment.acknowledged.append(false)
                        segment.pendingCount += 1
                        segmentRecords.append(Recovered(record: record, position: number << 32 | UInt64(frame.index)))
                    case .versionMismatch(let event, let storedVersion, let currentVersion):
                        // Reported once for the segment below, as an undecodable record is.
                        mismatches.add(event: event, storedVersion: storedVersion, currentVersion: currentVersion)
                        segment.timestamps.append(.distantPast)
                        segment.acknowledged.append(true)
                    }
                } catch {
                    // Reported once for the segment below; it counts as delivered, so it never
                    // holds the segment back.
                    undecodable += 1
                    segment.timestamps.append(.distantPast)
                    segment.acknowledged.append(true)
                }
            }
            if undecodable > 0 {
                reports.append(.undecodable(recordCount: undecodable))
            }
            reports += mismatches.reports
            guard segment.pendingCount > 0 else {
                try path.removeFile()
                continue
            }
            state.segments.append(segment)
            state.byteCount += segment.byteCount
            records.append(segmentRecords)
        }
        return (state, records)
    }
}
