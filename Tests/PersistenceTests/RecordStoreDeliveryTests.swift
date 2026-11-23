import Afluent
import DestinationTesting
import Destinations
import Events
import Foundation
import Persistence
import Synchronization
import Testing
import Trackers

@Suite("RecordStore: delivery", .timeLimit(.minutes(1)))
struct RecordStoreDeliveryTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    /// Holds every batch until `gate` opens, after announcing the first on `entered`; returns at
    /// once when cancelled.
    final class Stuck: Destination {
        let entered = SingleValueSubject<Void>()
        let gate = SingleValueSubject<Void>()
        let received = Mutex<[[Int]]>([])

        func receive(_ batch: [EventRecord]) async {
            try? entered.send()
            try? await gate.execute()
            received.withLock { $0.append(batch.compactMap { ($0.event as? Tapped)?.number }) }
        }
    }

    /// Fails to send each batch while offline, retrying each time `retry` yields, as a destination
    /// that handles its own errors does; announces every attempt on `attempts`.
    final class Flaky: Destination {
        let online = Mutex(false)
        let (retries, retry) = AsyncStream.makeStream(of: Void.self)
        let (attempts, attempted) = AsyncStream.makeStream(of: Int.self)
        let attemptCount = Mutex(0)
        let sent = Mutex<[[Int]]>([])

        func receive(_ batch: [EventRecord]) async {
            var retries = self.retries.makeAsyncIterator()
            while true {
                let attempt = attemptCount.withLock { count in
                    count += 1
                    return count
                }
                attempted.yield(attempt)
                if online.withLock({ $0 }) {
                    sent.withLock { $0.append(batch.compactMap { ($0.event as? Tapped)?.number }) }
                    return
                }
                guard await retries.next() != nil else { return }
            }
        }
    }

    @Test("A batch is acknowledged only once every destination has received it", arguments: StoreKind.all)
    func everyDestination(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let fast = InMemoryDestination()
        let slow = Stuck()
        let sut = tracker.records.batch(strategy: .count(2)).deliver(to: fast, slow)
        let delivery = Task { try await sut.execute() }
        var deliveries = fast.deliveries.makeAsyncIterator()

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        _ = await deliveries.next()
        try await slow.entered.execute()

        #expect(store.pendingRecordCount == 2)

        try slow.gate.send()
        await tracker.finish()
        try await delivery.value

        #expect(store.pendingRecordCount == 0)
        #expect(store.byteCount == 0)
    }

    @Test("A delivery to no destinations acknowledges each batch at once", arguments: StoreKind.all)
    func noDestinations(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)

        tracker.track(Tapped(number: 1))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver().execute()

        #expect(store.pendingRecordCount == 0)
        #expect(store.byteCount == 0)
    }

    @Test("A cancelled delivery acknowledges nothing it hadn't delivered, and the next run gets those records marked redelivered", arguments: StoreKind.all)
    func cancelledDelivery(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let destination = Stuck()
        let sut = tracker.records.batch(strategy: .count(2)).deliver(to: destination)
        let delivery = Task { try await sut.execute() }

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        try await destination.entered.execute()
        tracker.track(Tapped(number: 3))
        await tracker.flush()
        delivery.cancel()
        _ = try? await delivery.value

        #expect(store.pendingRecordCount == 3)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let recovered = next.takeRecoveredRecords()
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == [1, 2, 3])
        #expect(recovered.map(\.isRedelivered) == [true, true, false])
    }

    @Test("A record is marked as being delivered before any destination receives it", arguments: StoreKind.all)
    func markedBeforeReceive(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let destination = Stuck()
        let sut = tracker.records.batch(strategy: .count(1)).deliver(to: destination)
        let delivery = Task { try await sut.execute() }

        tracker.track(Tapped(number: 1))
        try await destination.entered.execute()

        // A copy of the store as it is now, as a crash would leave it: a second store mustn't open
        // it while this one has it.
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        #expect(next.takeRecoveredRecords().map(\.isRedelivered) == [true])
        try destination.gate.send()
        await tracker.finish()
        try await delivery.value
    }

    @Test("A batch a full destination buffer dropped is never acknowledged, so it stays for the next launch, marked redelivered", arguments: StoreKind.all)
    func droppedBatchKept(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let destination = Stuck()
        // The delivery asks for a fourth batch once it has put the third in the buffer.
        let reads = Mutex(0)
        let thirdBuffered = SingleValueSubject<Void>()
        let sut = tracker.records.batch(strategy: .count(1))
            .handleEvents(receiveNext: {
                if reads.withLock({ reads in
                    reads += 1
                    return reads
                }) == 4 {
                    try? thirdBuffered.send()
                }
            })
            .deliver(to: destination, batchBufferLimit: 1)
        let delivery = Task { try await sut.execute() }

        tracker.track(Tapped(number: 1))
        try await destination.entered.execute()
        // 2 waits in the buffer until 3 replaces it.
        tracker.track(Tapped(number: 2))
        tracker.track(Tapped(number: 3))
        try await thirdBuffered.execute()
        await tracker.finish()
        try destination.gate.send()
        try await delivery.value

        #expect(destination.received.withLock { $0 }.flatMap { $0 } == [1, 3])
        #expect(store.pendingRecordCount == 1)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let recovered = next.takeRecoveredRecords()
        // A segment comes back whole, with its delivered records too; a table only with the
        // record never acknowledged.
        let expected = kind == .segments ? [1, 2, 3] : [2]
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == expected)
        let allRedelivered = recovered.allSatisfy(\.isRedelivered)
        #expect(allRedelivered)
    }

    @Test("While the destination is offline, records stay on disk within the bound, the oldest dropped and reported, until a send succeeds", arguments: StoreKind.all)
    func offlinePeriod(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let timestamp = Date(timeIntervalSince1970: 0)
        // Room for three records, tracked from this function as the probe is, and their marks.
        let opened = try await kind.open(at: path, events: [Tapped.self], holding: 3) { probe in
            let measuring = Tracker(store: probe, now: { timestamp })
            measuring.track(Tapped(number: 0))
            await measuring.finish()
        }
        let store = opened.store
        let tracker = Tracker(store: store, now: { timestamp })
        let destination = Flaky()
        let sut = tracker.records.batch(strategy: .count(6)).deliver(to: destination)
        let delivery = Task { try await sut.execute() }
        var attempts = destination.attempts.makeAsyncIterator()
        var reports = store.dropReports.makeAsyncIterator()
        let expectedReport = DropReport.sizeBound(recordCount: 1, timestamps: timestamp...timestamp)

        for number in 1...6 {
            tracker.track(Tapped(number: number))
        }
        #expect(await attempts.next() == 1)
        destination.retry.yield()
        #expect(await attempts.next() == 2)

        let actualReports = [await reports.next(), await reports.next(), await reports.next()]
        #expect(actualReports == [expectedReport, expectedReport, expectedReport])
        #expect(store.pendingRecordCount == 3)
        #expect(store.byteCount <= opened.byteBound)
        // A copy of the store as it is now, as a crash would leave it: a second store mustn't open
        // it while this one has it.
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let offline = try kind.open(at: copy, events: [Tapped.self]).store
        let recovered = offline.takeRecoveredRecords()
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == [4, 5, 6])
        #expect(recovered.map(\.isRedelivered) == [true, true, true])

        destination.online.withLock { $0 = true }
        destination.retry.yield()
        await tracker.finish()
        try await delivery.value

        // The dropped records were still in memory, so this run delivers them all.
        #expect(destination.sent.withLock { $0 } == [[1, 2, 3, 4, 5, 6]])
        #expect(store.pendingRecordCount == 0)
        #expect(store.byteCount == 0)
    }

    @Test("Records delivered from a store carry its tag and aren't redelivered", arguments: StoreKind.all)
    func deliveredRecords(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tracker = Tracker(store: try kind.open(at: path, events: [Tapped.self]).store)
        let destination = InMemoryDestination()

        tracker.track(Tapped(number: 1))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: destination).execute()

        let actual = try #require(destination.records.first)
        #expect(actual.deliveryTag != nil)
        #expect(!actual.isRedelivered)
    }
}

extension RecordStoreDeliveryTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
    }
}
