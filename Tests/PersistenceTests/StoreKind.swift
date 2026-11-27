// Fixture data for the behaviour tests every RecordStore must pass (RecordStore*Tests): each runs
// once per kind of store, as a parameterized test. Kept in this target rather than in
// TraffluentTestSupport, which every test target links: there it would bring GRDB to all of them.

import AsyncQueues
import Events
import Foundation
import Persistence
import SystemPackage
import Testing

#if canImport(GRDB)
import GRDB
import GRDBPersistence
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// What the behaviour tests read from a store, beyond `RecordStore`.
protocol InspectableStore: RecordStore {
    var byteCount: Int { get }
    var pendingRecordCount: Int { get }
    var dropReports: AsyncQueue<DropReport> { get }
}

extension SegmentStore: InspectableStore {}

#if canImport(GRDB)
extension DatabaseStore: InspectableStore {}
#endif

/// A store a test opened, and how to make its writes fail.
struct OpenedStore {
    let store: any InspectableStore
    /// The store's bound.
    let byteBound: Int
    /// Makes every later write of the store fail, as a full disk does. A segment store's failure
    /// lowers the process's file-size limit, so call it only in an exit test's child.
    let failWrites: () -> Void
}

/// A kind of `RecordStore`, kept in a directory of its own.
enum StoreKind: String, Codable, Sendable, CustomTestStringConvertible {
    /// `SegmentStore`: segment files in the directory.
    case segments
    #if canImport(GRDB)
    /// `DatabaseStore` in a `DatabaseQueue` on `records.sqlite` in the directory (rollback journal).
    case databaseQueue
    /// `DatabaseStore` in a `DatabasePool` on `records.sqlite` in the directory (WAL).
    case databasePool
    #endif

    /// Every kind this platform builds.
    static var all: [StoreKind] {
        #if canImport(GRDB)
        [.segments, .databaseQueue, .databasePool]
        #else
        [.segments]
        #endif
    }

    var testDescription: String {
        rawValue
    }

    /// A new directory's path under the temporary directory, for one test.
    static func temporaryPath() -> String {
        FilePath(NSTemporaryDirectory()).appending("RecordStoreTests-\(UUID().uuidString)").string
    }

    /// Opens a store of this kind in the directory at `path`, creating it; it recovers what an
    /// earlier store left there.
    ///
    /// - Parameters:
    ///   - path: The directory.
    ///   - events: The event types the store keeps.
    ///   - byteBound: The store's bound, or its default when `nil`.
    ///   - segmentByteCount: A segment store's segment size, or its default when `nil`.
    func open(at path: String, events: [any (Event & Codable).Type], byteBound: Int? = nil, segmentByteCount: Int? = nil) throws -> OpenedStore {
        switch self {
        case .segments:
            let bound = byteBound ?? SegmentStore.defaultByteBound
            let store = try SegmentStore(events: events, directory: FilePath(path), byteBound: bound, segmentByteCount: segmentByteCount)
            return OpenedStore(store: store, byteBound: bound) {
                signal(SIGXFSZ, SIG_IGN)
                var limit = rlimit()
                #if canImport(Glibc)
                getrlimit(__rlimit_resource_t(RLIMIT_FSIZE.rawValue), &limit)
                limit.rlim_cur = rlim_t(store.byteCount)
                setrlimit(__rlimit_resource_t(RLIMIT_FSIZE.rawValue), &limit)
                #else
                getrlimit(RLIMIT_FSIZE, &limit)
                limit.rlim_cur = rlim_t(store.byteCount)
                setrlimit(RLIMIT_FSIZE, &limit)
                #endif
            }
        #if canImport(GRDB)
        case .databaseQueue, .databasePool:
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            let file = FilePath(path).appending("records.sqlite").string
            let database: any DatabaseWriter = self == .databaseQueue ? try DatabaseQueue(path: file) : try DatabasePool(path: file)
            let bound = byteBound ?? DatabaseStore.defaultByteBound
            let store = try DatabaseStore(events: events, database: database, byteBound: bound)
            return OpenedStore(store: store, byteBound: bound) {
                // Every later statement that writes fails with SQLITE_READONLY.
                try? database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 1") }
            }
        #endif
        }
    }

    /// Opens a store of this kind in the directory at `path` whose bound holds exactly `count`
    /// records the size of the one `probe` writes, with room for a delivery mark of each; a
    /// segment store holds one record per segment, so the oldest record is the oldest segment.
    ///
    /// - Parameters:
    ///   - path: The directory.
    ///   - events: The event types the store keeps.
    ///   - count: How many records the bound holds.
    ///   - probe: Writes one record to the store it is given, as the test writes its records.
    func open(at path: String, events: [any (Event & Codable).Type], holding count: Int, probe: (any InspectableStore) async -> Void) async throws -> OpenedStore {
        let probePath = path + "-probe"
        defer { try? FileManager.default.removeItem(atPath: probePath) }
        let measured = try open(at: probePath, events: events).store
        await probe(measured)
        let recordByteCount = measured.byteCount
        switch self {
        case .segments:
            // A delivery mark of one record: its frame's length and checksum, its kind, a number.
            let mark = 8 + 1 + 4
            return try open(at: path, events: events, byteBound: count * (recordByteCount + mark), segmentByteCount: recordByteCount)
        #if canImport(GRDB)
        case .databaseQueue, .databasePool:
            return try open(at: path, events: events, byteBound: count * recordByteCount)
        #endif
        }
    }
}
