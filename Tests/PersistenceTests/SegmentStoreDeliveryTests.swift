import Afluent
import DestinationTesting
import Destinations
import Events
import Foundation
import Persistence
import Synchronization
import SystemPackage
import Testing
import Trackers

@Suite("SegmentStore: delivery", .timeLimit(.minutes(1)))
struct SegmentStoreDeliveryTests {
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

    @Test("A batch is acknowledged only once every destination has received it")
    func everyDestination() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
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
        tracker.finish()
        try await delivery.value

        #expect(store.pendingRecordCount == 0)
        #expect(store.byteCount == 0)
    }

    @Test("A delivery to no destinations acknowledges each batch at once")
    func noDestinations() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        let tracker = Tracker(store: store)

        tracker.track(Tapped(number: 1))
        tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver().execute()

        #expect(store.pendingRecordCount == 0)
        #expect(store.byteCount == 0)
    }

    @Test("A cancelled delivery acknowledges nothing it hadn't delivered, and the next run gets those records marked redelivered")
    func cancelledDelivery() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        let tracker = Tracker(store: store)
        let destination = Stuck()
        let sut = tracker.records.batch(strategy: .count(2)).deliver(to: destination)
        let delivery = Task { try await sut.execute() }

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        try await destination.entered.execute()
        tracker.track(Tapped(number: 3))
        delivery.cancel()
        _ = try? await delivery.value

        #expect(store.pendingRecordCount == 3)
        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        let recovered = next.takeRecoveredRecords()
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == [1, 2, 3])
        #expect(recovered.map(\.isRedelivered) == [true, true, false])
    }

    @Test("A record is marked as being delivered before any destination receives it")
    func markedBeforeReceive() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        let tracker = Tracker(store: store)
        let destination = Stuck()
        let sut = tracker.records.batch(strategy: .count(1)).deliver(to: destination)
        let delivery = Task { try await sut.execute() }

        tracker.track(Tapped(number: 1))
        try await destination.entered.execute()

        // A copy of the log as it is now, as a crash would leave it: a second store mustn't open
        // the directory while this one has it.
        let copy = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: copy.string) }
        try FileManager.default.copyItem(atPath: directory.string, toPath: copy.string)
        let next = try SegmentStore(events: [Tapped.self], directory: copy)
        #expect(next.takeRecoveredRecords().map(\.isRedelivered) == [true])
        try destination.gate.send()
        tracker.finish()
        try await delivery.value
    }

    @Test("Marking records as being delivered, without acknowledging them, brings them back redelivered; the others not")
    func willDeliverMarks() throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        _ = probe.append(EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let frame = probe.byteCount - 8
        let log = directory.appending("log")
        let sut = try SegmentStore(events: [Tapped.self], directory: log, segmentByteCount: 8 + 2 * frame)
        let tags = try (0..<4).map { number in
            try #require(sut.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)).deliveryTag)
        }

        _ = tags[0].acknowledger.willDeliver([tags[1].position, tags[2].position])

        let next = try SegmentStore(events: [Tapped.self], directory: log)
        #expect(next.takeRecoveredRecords().map(\.isRedelivered) == [false, true, true, false])
    }

    @Test("A batch a full destination buffer dropped is never acknowledged, so its segment stays for the next launch")
    func droppedBatchKept() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
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
        tracker.finish()
        try destination.gate.send()
        try await delivery.value

        #expect(destination.received.withLock { $0 }.flatMap { $0 } == [1, 3])
        #expect(store.pendingRecordCount == 1)
        // The segment comes back whole, with the delivered records too, all marked redelivered.
        let next = try SegmentStore(events: [Tapped.self], directory: directory)
        let recovered = next.takeRecoveredRecords()
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == [1, 2, 3])
        #expect(recovered.map(\.isRedelivered) == [true, true, true])
    }

    @Test("While the destination is offline, records stay on disk within the bound, the oldest dropped and reported, until a send succeeds")
    func offlinePeriod() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let timestamp = Date(timeIntervalSince1970: 0)
        // A record's frame, tracked from this function as the ones below are.
        let probe = try SegmentStore(events: [Tapped.self], directory: directory.appending("probe"))
        Tracker(store: probe, now: { timestamp }).track(Tapped(number: 0))
        let frame = probe.byteCount - 8
        // One record per segment, room for three, and for a delivery mark of one record in each.
        let segment = 8 + frame
        let mark = 8 + 1 + 4
        let bound = 3 * (segment + mark)
        let log = directory.appending("log")
        let store = try SegmentStore(events: [Tapped.self], directory: log, byteBound: bound, segmentByteCount: segment)
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
        #expect(store.byteCount <= bound)
        // A copy of the log as it is now, as a crash would leave it: a second store mustn't open
        // the directory while this one has it.
        let copy = directory.appending("copy")
        try FileManager.default.copyItem(atPath: log.string, toPath: copy.string)
        let offline = try SegmentStore(events: [Tapped.self], directory: copy)
        let recovered = offline.takeRecoveredRecords()
        #expect(recovered.compactMap { ($0.event as? Tapped)?.number } == [4, 5, 6])
        #expect(recovered.map(\.isRedelivered) == [true, true, true])

        destination.online.withLock { $0 = true }
        destination.retry.yield()
        tracker.finish()
        try await delivery.value

        // The dropped records were still in memory, so this run delivers them all.
        #expect(destination.sent.withLock { $0 } == [[1, 2, 3, 4, 5, 6]])
        #expect(store.pendingRecordCount == 0)
        #expect(store.byteCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: log.string).isEmpty)
    }

    @Test("Records delivered from a store carry its tag and aren't redelivered")
    func deliveredRecords() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStoreDeliveryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let tracker = Tracker(store: try SegmentStore(events: [Tapped.self], directory: directory))
        let destination = InMemoryDestination()

        tracker.track(Tapped(number: 1))
        tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: destination).execute()

        let actual = try #require(destination.records.first)
        #expect(actual.deliveryTag != nil)
        #expect(!actual.isRedelivered)
    }
}

extension SegmentStoreDeliveryTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
    }
}
