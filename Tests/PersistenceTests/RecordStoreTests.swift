import Destinations
import Events
import Foundation
import Persistence
import Testing
import Trackers

// Behaviour every RecordStore must have, run against each kind of store (StoreKind). A test opens
// a second store on a copy of a directory, as the app's next launch would after a crash, so two
// stores never share one.

@Suite("RecordStore", .timeLimit(.minutes(1)))
struct RecordStoreTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    struct Untracked: Event {
        var number: Int
    }

    struct Retired: Event {
        var number: Int
    }

    @Test("The worker writes each record before publishing it, and a store opened next on it recovers it", arguments: StoreKind.all)
    func writeThrough(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let expected = [Tapped(number: 1)]

        tracker.track(Tapped(number: 1))
        await tracker.flush()

        #expect(store.pendingRecordCount == 1)
        #expect(store.byteCount > 0)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let recovered = next.takeRecoveredRecords()
        #expect(recovered.compactMap { $0.event as? Tapped } == expected)
        #expect(recovered.map(\.isRedelivered) == [false])
        #expect(next.pendingRecordCount == 1)
        #expect(next.byteCount == store.byteCount)
    }

    @Test("A recovered record keeps its timestamp and source location, in the top-level context", arguments: StoreKind.all)
    func recoveredFields(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expectedTimestamp = Date(timeIntervalSinceReferenceDate: 12_345.678)
        let expectedLocation = Events.SourceLocation(file: "/src/App/Checkout.swift", fileID: "App/Checkout.swift", function: "pay(for:)", line: 42, column: 7)
        let store = try kind.open(at: path, events: [Tapped.self]).store

        _ = store.append(EventRecord(event: Tapped(number: 3), timestamp: expectedTimestamp, sourceLocation: expectedLocation))

        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let actual = try #require(next.takeRecoveredRecords().first)
        #expect(actual.timestamp == expectedTimestamp)
        #expect(actual.sourceLocation == expectedLocation)
        #expect(actual.context.isEmpty)
        #expect(actual.name == "Tapped")
        #expect(actual.deliveryTag != nil)
    }

    @Test("A recovered record whose file equals its fileID keeps both", arguments: StoreKind.all)
    func recoveredFileEqualToFileID(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expectedLocation = Events.SourceLocation(file: "App/Checkout.swift", fileID: "App/Checkout.swift", function: "pay(for:)", line: 1, column: 1)
        let store = try kind.open(at: path, events: [Tapped.self]).store

        _ = store.append(EventRecord(event: Tapped(number: 3), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: expectedLocation))

        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let actual = try #require(next.takeRecoveredRecords().first)
        #expect(actual.sourceLocation == expectedLocation)
    }

    @Test("Recovered records are handed out once: a second take returns none", arguments: StoreKind.all)
    func takeOnce(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        _ = first.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)))
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let sut = try kind.open(at: copy, events: [Tapped.self]).store

        let taken = sut.takeRecoveredRecords()
        let actual = sut.takeRecoveredRecords()

        #expect(taken.count == 1)
        #expect(actual.isEmpty)
    }

    @Test("A tracker given a store delivers what earlier runs left first, then what it tracks", arguments: StoreKind.all)
    func recoveredFirst(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let earlier = Tracker(store: try kind.open(at: path, events: [Tapped.self]).store)
        earlier.track(Tapped(number: 1))
        earlier.track(Tapped(number: 2))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let destination = InMemoryDestination()
        let store = try kind.open(at: copy, events: [Tapped.self]).store
        let sut = Tracker(store: store)
        let expected = [Tapped(number: 1), Tapped(number: 2), Tapped(number: 3)]

        sut.track(Tapped(number: 3))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.events(of: Tapped.self) == expected)
        #expect(destination.records.map(\.isRedelivered) == [false, false, false])
        #expect(store.pendingRecordCount == 0)
    }

    @Test("Delivering every record empties the store: no bytes, no records, nothing for the next launch", arguments: StoreKind.all)
    func emptyAfterDelivery(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        // Several segments, for a segment store.
        let store = try kind.open(at: path, events: [Tapped.self], segmentByteCount: 200).store
        let tracker = Tracker(store: store)
        let destination = InMemoryDestination()

        for number in 0..<25 {
            tracker.track(Tapped(number: number))
        }
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.records.count == 25)
        #expect(store.byteCount == 0)
        #expect(store.pendingRecordCount == 0)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        #expect(next.takeRecoveredRecords().isEmpty)
        #expect(next.byteCount == 0)
    }

    @Test("Acknowledging records one at a time forgets each, and the last empties the store", arguments: StoreKind.all)
    func acknowledgedOneByOne(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let sut = try kind.open(at: path, events: [Tapped.self]).store
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let tags = try (0..<3).map { number in
            try #require(sut.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        }

        tags[1].acknowledger.acknowledge([tags[1].position])
        tags[0].acknowledger.acknowledge([tags[0].position])

        #expect(sut.pendingRecordCount == 1)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let recovered: [Int] = next.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number }
        #expect(recovered.contains(2))

        tags[2].acknowledger.acknowledge([tags[2].position])

        #expect(sut.pendingRecordCount == 0)
        #expect(sut.byteCount == 0)
    }

    @Test("Acknowledging a record twice, or a position the store never held, changes nothing", arguments: StoreKind.all)
    func repeatedAcknowledgement(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let sut = try kind.open(at: path, events: [Tapped.self]).store
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let records = (0..<2).map { sut.append(EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)) }
        let tag = try #require(records[0].deliveryTag)
        tag.acknowledger.acknowledge([tag.position])
        let expectedByteCount = sut.byteCount

        tag.acknowledger.acknowledge([tag.position, tag.position + 100, 99 << 32])

        #expect(sut.pendingRecordCount == 1)
        #expect(sut.byteCount == expectedByteCount)
        #expect(sut.byteCount > 0)
    }

    @Test("A record appended after the store was emptied is kept, and recovered on the next launch", arguments: StoreKind.all)
    func appendAfterEmptied(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let sut = try kind.open(at: path, events: [Tapped.self]).store
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let first = try #require(sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        first.acknowledger.acknowledge([first.position])

        let second = sut.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))

        #expect(second.deliveryTag != nil)
        #expect(sut.pendingRecordCount == 1)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        #expect(next.takeRecoveredRecords().compactMap { $0.event as? Tapped } == [Tapped(number: 2)])
    }

    @Test("An event type not in the store's list stays in memory only: delivered in this run, never written, not recovered", arguments: StoreKind.all)
    func memoryOnly(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let destination = InMemoryDestination()

        tracker.track(Untracked(number: 1))
        await tracker.finish()

        #expect(store.byteCount == 0)
        #expect(store.pendingRecordCount == 0)
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()
        #expect(destination.events(of: Untracked.self).map(\.number) == [1])
        #expect(destination.records.map { $0.deliveryTag == nil } == [true])
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        #expect(next.takeRecoveredRecords().isEmpty)
    }

    @Test("An event type not in the store's list produces no drop report", arguments: StoreKind.all)
    func memoryOnlyNotReported(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let sut = try await kind.open(at: path, events: [Tapped.self], holding: 1) { store in
            _ = store.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }.store
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1)...Date(timeIntervalSince1970: 1))

        _ = sut.append(EventRecord(event: Untracked(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
        _ = sut.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: location))

        // The first report is the Tapped record the bound dropped: the untracked event made none.
        let actual = await reports.next()
        #expect(actual == expected)
    }

    @Test("Records of an event type the next launch's store doesn't list are dropped and reported as undecodable", arguments: StoreKind.all)
    func undecodable(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try kind.open(at: path, events: [Tapped.self, Retired.self]).store
        _ = earlier.append(EventRecord(event: Retired(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = earlier.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        _ = earlier.append(EventRecord(event: Retired(number: 3), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let expected = DropReport.undecodable(recordCount: 2)

        let sut = try kind.open(at: copy, events: [Tapped.self]).store

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().compactMap { $0.event as? Tapped } == [Tapped(number: 2)])
        #expect(sut.pendingRecordCount == 1)
    }

    @Test("Synchronizing keeps every record", arguments: StoreKind.all)
    func synchronize(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let sut = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: sut)
        tracker.track(Tapped(number: 1))
        await tracker.flush()

        sut.synchronize()
        sut.synchronize()

        #expect(sut.pendingRecordCount == 1)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        #expect(next.takeRecoveredRecords().count == 1)
    }

    @Test("An event tracked after finish is dropped: neither delivered in this run nor written for the next", arguments: StoreKind.all)
    func trackedAfterFinish(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tracker = Tracker(store: try kind.open(at: path, events: [Tapped.self]).store)
        let destination = InMemoryDestination()

        await tracker.finish()
        tracker.track(Tapped(number: 1))
        try await tracker.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        #expect(destination.records.isEmpty)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        #expect(next.takeRecoveredRecords().isEmpty)
    }
}

extension RecordStoreTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
    }
}

extension RecordStoreTests.Retired: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
    }
}
