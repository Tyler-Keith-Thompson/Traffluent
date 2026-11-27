import Afluent
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
        let entering = Mutex<[[UUID]]>([])
        let receivedRecords = Mutex<[EventRecord]>([])

        func receive(_ batch: [EventRecord]) async {
            entering.withLock { $0.append(batch.map(\.id)) }
            try? entered.send()
            try? await gate.execute()
            received.withLock { $0.append(batch.compactMap { ($0.event as? Tapped)?.number }) }
            receivedRecords.withLock { $0 += batch }
        }
    }

    /// Holds each batch until the test lets one through on `pass`, after announcing its numbers
    /// on `entries`; returns at once when cancelled.
    final class Turnstile: Destination {
        let (entries, entered) = AsyncStream.makeStream(of: [Int].self)
        let (passes, pass) = AsyncStream.makeStream(of: Void.self)

        func receive(_ batch: [EventRecord]) async {
            entered.yield(batch.compactMap { ($0.event as? Tapped)?.number })
            var passes = self.passes.makeAsyncIterator()
            _ = await passes.next()
        }
    }

    /// Not one of the store's events, so its records are kept in memory only.
    struct Unlisted: Event {}

    struct SignedUp: Event {
        var email: Sensitive<String>
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

    @Test("A record whose delivery didn't finish reaches the next run's destinations redelivered, with the identifier it was first delivered with", arguments: StoreKind.all)
    func redeliveredIdentifiers(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tracker = Tracker(store: try kind.open(at: path, events: [Tapped.self]).store)
        let stuck = Stuck()
        let delivery = Task { try await tracker.records.batch(strategy: .count(2)).deliver(to: stuck).execute() }
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        try await stuck.entered.execute()
        delivery.cancel()
        _ = try? await delivery.value
        await tracker.finish()
        let expected = try #require(stuck.entering.withLock { $0.first })
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = Tracker(store: try kind.open(at: copy, events: [Tapped.self]).store)
        let destination = InMemoryDestination()

        await next.finish()
        try await next.records.batch(strategy: .count(10)).deliver(to: destination).execute()

        let actual = destination.records
        #expect(actual.map(\.id) == expected)
        #expect(actual.map(\.isRedelivered) == [true, true])
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

    @Test("A batch a full destination buffer dropped reaches that destination from the store once it has caught up, in this run, and is then forgotten", arguments: StoreKind.all)
    func droppedBatchRedelivered(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store, now: { timestamp })
        let destination = Stuck()
        let sut = try tracker.records.batch(strategy: .count(1)).deliver(to: destination, batchBufferLimit: 1)
        let reports = sut.bufferDropReports
        let expectedReport = BufferDropReport(destinationIndex: 0, recordCount: 1, timestamps: timestamp...timestamp, storedRecordCount: 1)
        let expectedReceived = [[1], [3], [2]]
        let expectedPendingWhileBehind = 3
        let expectedPending = 0
        let expectedByteCount = 0
        let delivery = Task { try await sut.execute() }
        var received = reports.makeAsyncIterator()
        tracker.track(Tapped(number: 1))
        try await destination.entered.execute()
        // 2 waits in the buffer until 3 replaces it.
        tracker.track(Tapped(number: 2))
        tracker.track(Tapped(number: 3))
        let actualReport = await received.next()
        let actualPendingWhileBehind = store.pendingRecordCount

        try destination.gate.send()
        await tracker.finish()
        try await delivery.value

        let actualReceived = destination.received.withLock { $0 }
        let actualRedelivered = try #require(destination.receivedRecords.withLock { $0.last })
        #expect(actualReport == expectedReport)
        #expect(actualPendingWhileBehind == expectedPendingWhileBehind)
        #expect(actualReceived == expectedReceived)
        #expect(!actualRedelivered.isRedelivered)
        #expect(actualRedelivered.deliveryTag != nil)
        #expect(store.pendingRecordCount == expectedPending)
        #expect(store.byteCount == expectedByteCount)
    }

    @Test("With two destinations, a batch one's full buffer dropped is sent again to that one alone, and forgotten once both have it", arguments: StoreKind.all)
    func droppedBatchRedeliveredOnce(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let fast = InMemoryDestination()
        let slow = Stuck()
        let sut = try tracker.records.batch(strategy: .count(1)).deliver(to: fast, slow, batchBufferLimit: 1)
        let reports = sut.bufferDropReports
        let expectedSlow = [[1], [3], [2]]
        let expectedNumbers = [1, 2, 3]
        // 1 is still being received by the slow destination, 2 was dropped, 3 waits.
        let expectedPendingWhileBehind = 3
        let expectedPending = 0
        let expectedByteCount = 0
        let delivery = Task { try await sut.execute() }
        var received = reports.makeAsyncIterator()
        tracker.track(Tapped(number: 1))
        try await slow.entered.execute()
        tracker.track(Tapped(number: 2))
        tracker.track(Tapped(number: 3))
        // The fast destination's buffer may drop a batch too, which it is then sent again; the
        // slow one's buffer drops 2.
        while let report = await received.next(), report.destinationIndex != 1 {}
        let actualPendingWhileBehind = store.pendingRecordCount

        try slow.gate.send()
        await tracker.finish()
        try await delivery.value

        let actualFast = fast.records
        let actualSlowRecords = slow.receivedRecords.withLock { $0 }
        let actualSlow = slow.received.withLock { $0 }
        let actualFastNumbers = actualFast.compactMap { ($0.event as? Tapped)?.number }.sorted()
        let fastIDs = actualFast.map(\.id)
        let noneRedelivered = (actualFast + actualSlowRecords).allSatisfy { !$0.isRedelivered }
        #expect(actualPendingWhileBehind == expectedPendingWhileBehind)
        #expect(actualSlow == expectedSlow)
        #expect(actualFastNumbers == expectedNumbers)
        #expect(Set(fastIDs).count == fastIDs.count)
        #expect(Set(fastIDs) == Set(actualSlowRecords.map(\.id)))
        #expect(noneRedelivered)
        #expect(store.pendingRecordCount == expectedPending)
        #expect(store.byteCount == expectedByteCount)
    }

    @Test("Of a batch a full destination buffer dropped, the records the store keeps are sent again and the ones in memory only are reported lost", arguments: StoreKind.all)
    func droppedBatchPartlyStored(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store, now: { timestamp })
        let destination = Stuck()
        let sut = try tracker.records.batch(strategy: .count(2)).deliver(to: destination, batchBufferLimit: 1)
        let reports = sut.bufferDropReports
        let expectedReport = BufferDropReport(destinationIndex: 0, recordCount: 2, timestamps: timestamp...timestamp, storedRecordCount: 1)
        let expectedReceived = [[1, 2], [5, 6], [3]]
        let expectedRecordCounts = [2, 2, 1]
        let expectedPending = 0
        let delivery = Task { try await sut.execute() }
        var received = reports.makeAsyncIterator()
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        try await destination.entered.execute()
        tracker.track(Tapped(number: 3))
        tracker.track(Unlisted())
        tracker.track(Tapped(number: 5))
        tracker.track(Tapped(number: 6))
        let actualReport = await received.next()

        try destination.gate.send()
        await tracker.finish()
        try await delivery.value

        let actualReceived = destination.received.withLock { $0 }
        let actualRecordCounts = destination.entering.withLock { $0 }.map(\.count)
        #expect(actualReport == expectedReport)
        #expect(actualReceived == expectedReceived)
        #expect(actualRecordCounts == expectedRecordCounts)
        #expect(store.pendingRecordCount == expectedPending)
    }

    @Test("A record of a dropped batch the store's bound drops before it is read back is neither sent nor counted, and the batch's others are sent and forgotten", arguments: StoreKind.all)
    func droppedBatchPartlyEvicted(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let timestamp = Date(timeIntervalSince1970: 1_000)
        // Room for five records, tracked from this function as the probe is, and their marks.
        let opened = try await kind.open(at: path, events: [Tapped.self], holding: 5) { probe in
            let measuring = Tracker(store: probe, now: { timestamp })
            measuring.track(Tapped(number: 0))
            await measuring.finish()
        }
        let store = opened.store
        let tracker = Tracker(store: store, now: { timestamp })
        let destination = Stuck()
        let sut = try tracker.records.batch(strategy: .count(2)).deliver(to: destination, batchBufferLimit: 1)
        let reports = sut.bufferDropReports
        // [1, 2] is received; [3, 4] and then [5, 6] are dropped; [7, 8] waits. Tracking 6, 7 and
        // 8 makes the bound drop 1, 2 and 3.
        let expectedReceived = [[1, 2], [7, 8], [4], [5, 6]]
        let expectedPending = 0
        let delivery = Task { try await sut.execute() }
        var received = reports.makeAsyncIterator()
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        try await destination.entered.execute()
        for number in 3 ... 8 {
            tracker.track(Tapped(number: number))
        }
        // Drops no one has read merge, so the reports are read until they count both batches.
        var dropped = 0
        while dropped < 4, let report = await received.next() {
            dropped += report.recordCount
        }
        await tracker.flush()

        try destination.gate.send()
        await tracker.finish()
        try await delivery.value

        let actualReceived = destination.received.withLock { $0 }
        #expect(actualReceived == expectedReceived)
        #expect(store.pendingRecordCount == expectedPending)
    }

    @Test("Cancelling the delivery while a dropped batch is being sent again leaves its records unacknowledged, for the next launch", arguments: StoreKind.all)
    func cancelledRedelivery(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let destination = Turnstile()
        let sut = try tracker.records.batch(strategy: .count(1)).deliver(to: destination, batchBufferLimit: 1)
        let reports = sut.bufferDropReports
        let expectedRedelivered = [2]
        let expectedPending = 1
        let delivery = Task { try await sut.execute() }
        var entries = destination.entries.makeAsyncIterator()
        var received = reports.makeAsyncIterator()
        tracker.track(Tapped(number: 1))
        _ = await entries.next()
        tracker.track(Tapped(number: 2))
        tracker.track(Tapped(number: 3))
        _ = await received.next()
        destination.pass.yield()
        _ = await entries.next()
        destination.pass.yield()
        let actualRedelivered = await entries.next()

        delivery.cancel()
        _ = try? await delivery.value
        await tracker.finish()

        #expect(actualRedelivered == expectedRedelivered)
        #expect(store.pendingRecordCount == expectedPending)
    }

    @Test("A recovered record a full destination buffer dropped is sent again still marked redelivered", arguments: StoreKind.all)
    func droppedRecoveredRecord(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let earlier = Tracker(store: try kind.open(at: path, events: [Tapped.self]).store)
        let interrupted = Stuck()
        let cancelled = Task { try await earlier.records.batch(strategy: .count(2)).deliver(to: interrupted).execute() }
        earlier.track(Tapped(number: 1))
        earlier.track(Tapped(number: 2))
        try await interrupted.entered.execute()
        earlier.track(Tapped(number: 3))
        await earlier.flush()
        cancelled.cancel()
        _ = try? await cancelled.value
        await earlier.finish()
        // A copy, as the app ending would leave the store: a second store mustn't open it while
        // the first has it.
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let store = try kind.open(at: copy, events: [Tapped.self]).store
        let tracker = Tracker(store: store)
        let destination = Stuck()
        let sut = try tracker.records.batch(strategy: .count(1)).deliver(to: destination, batchBufferLimit: 1)
        let reports = sut.bufferDropReports
        let expectedReceived = [[1], [3], [2]]
        let expectedRedelivered = [true, false, true]
        let expectedPending = 0
        var received = reports.makeAsyncIterator()
        // The recovered records come first: 1 is received, 2 waits, and 3 replaces it.
        let delivery = Task { try await sut.execute() }
        try await destination.entered.execute()
        _ = await received.next()

        try destination.gate.send()
        await tracker.finish()
        try await delivery.value

        let actualReceived = destination.received.withLock { $0 }
        let actualRedelivered = destination.receivedRecords.withLock { $0 }.map(\.isRedelivered)
        #expect(actualReceived == expectedReceived)
        #expect(actualRedelivered == expectedRedelivered)
        #expect(store.pendingRecordCount == expectedPending)
    }

    @Test("A record a full destination buffer dropped reveals its sensitive values once sent again, unless the destination redacts them", arguments: StoreKind.all)
    func droppedSensitiveRecord(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Tapped.self, SignedUp.self]).store
        let tracker = Tracker(store: store)
        let revealing = Stuck()
        let redacted = InMemoryDestination()
        let sut = try tracker.records.batch(strategy: .count(1)).deliver(to: revealing, redacted.redactingSensitiveValues(), batchBufferLimit: 1)
        let reports = sut.bufferDropReports
        let expected = "ada@example.com"
        let delivery = Task { try await sut.execute() }
        var received = reports.makeAsyncIterator()
        tracker.track(Tapped(number: 1))
        try await revealing.entered.execute()
        tracker.track(SignedUp(email: Sensitive(expected)))
        tracker.track(Tapped(number: 3))
        while let report = await received.next(), report.destinationIndex != 0 {}

        try revealing.gate.send()
        await tracker.finish()
        try await delivery.value

        let revealingRecord = try #require(revealing.receivedRecords.withLock { $0.last })
        let redactedRecord = try #require(redacted.records.first { $0.event is SignedUp })
        let event = try #require(revealingRecord.event as? SignedUp)
        let actual = revealingRecord.reveal(event.email)
        let actualRedacted = redactedRecord.reveal(event.email)
        #expect(actual == expected)
        #expect(actualRedacted == nil)
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

extension RecordStoreDeliveryTests.Tapped: Codable {}

extension RecordStoreDeliveryTests.SignedUp: Codable {}
