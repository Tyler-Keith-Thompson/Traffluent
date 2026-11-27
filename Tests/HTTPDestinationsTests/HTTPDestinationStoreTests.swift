import Afluent
import Clocks
import Destinations
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import Persistence
import Synchronization
import SystemPackage
import Testing
import Trackers

@Suite("HTTPDestination: with a store", .timeLimit(.minutes(1)))
struct HTTPDestinationStoreTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    /// Encodes a batch as its records' identifiers and redelivery markers, one record per line,
    /// as plain text.
    struct IdentifiersEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            BatchRequests(requests: [EncodedRequest(body: body(of: batch), recordIDs: batch.map(\.id))], skippedRecords: [])
        }

        func body(of batch: [EventRecord]) -> EncodedBatch {
            let lines = batch.map { "\($0.id.uuidString) \($0.isRedelivered)" }
            return EncodedBatch(body: Data(lines.joined(separator: "\n").utf8), contentType: "text/plain")
        }
    }

    /// Answers the nth request with the nth result of `script`, and every request past its end
    /// with its last; keeps each body and announces each request on `attempts`.
    final class ScriptedTransport: HTTPTransport {
        let script: [Result<HTTPResponse, HTTPTransportError>]
        let bodies = Mutex<[String]>([])
        let (attempts, attempted) = AsyncStream.makeStream(of: Int.self)

        init(_ script: [Result<HTTPResponse, HTTPTransportError>]) {
            self.script = script
        }

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            let attempt = bodies.withLock { bodies in
                bodies.append(String(decoding: body, as: UTF8.self))
                return bodies.count
            }
            attempted.yield(attempt)
            return try script[min(attempt, script.count) - 1].get()
        }
    }

    @Test("Records whose send failed for now stay in the store while the batch is retried, and are forgotten once a later send delivers them")
    func keptUntilDelivered() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("HTTPDestinationStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        let tracker = Tracker(store: store)
        let transport = ScriptedTransport([.failure(.failed(reason: "offline")), .success(HTTPResponse(status: .serviceUnavailable)), .success(HTTPResponse(status: .ok))])
        let sut = HTTPDestination(endpoint: endpoint, transport: transport, encoder: IdentifiersEncoder(), clock: clock)
        let delivery = tracker.records.batch(strategy: .count(2)).deliver(to: sut)
        var attempts = transport.attempts.makeAsyncIterator()
        let expectedWhileRetried = [2, 2]
        let expectedAfter = 0
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        let running = Task { try await delivery.execute() }
        var actualWhileRetried: [Int] = []

        for wait in [Duration.seconds(1), .seconds(2)] {
            _ = await attempts.next()
            while (try? await clock.checkSuspension()) != nil {}
            actualWhileRetried.append(store.pendingRecordCount)
            await clock.advance(by: wait)
        }
        await tracker.finish()
        try await running.value

        #expect(actualWhileRetried == expectedWhileRetried)
        #expect(store.pendingRecordCount == expectedAfter)
        #expect(store.byteCount == expectedAfter)
    }

    @Test("Records still being retried when the app ends come back on the next launch, marked redelivered, with their identifiers, and are delivered then")
    func redeliveredAfterRelaunch() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("HTTPDestinationStoreTests-\(UUID().uuidString)")
        let relaunched = FilePath(directory.string + "-relaunched")
        defer {
            try? FileManager.default.removeItem(atPath: directory.string)
            try? FileManager.default.removeItem(atPath: relaunched.string)
        }
        let endpoint = try #require(URL(string: "https://collector.example.com/batches"))
        let clock = TestClock()
        let store = try SegmentStore(events: [Tapped.self], directory: directory)
        let tracker = Tracker(store: store)
        let offline = ScriptedTransport([.failure(.failed(reason: "offline"))])
        let delivery = tracker.records.batch(strategy: .count(2))
            .deliver(to: HTTPDestination(endpoint: endpoint, transport: offline, encoder: IdentifiersEncoder(), clock: clock))
        var attempts = offline.attempts.makeAsyncIterator()
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        let running = Task { try await delivery.execute() }
        _ = await attempts.next()
        while (try? await clock.checkSuspension()) != nil {}
        let firstBody = try #require(offline.bodies.withLock { $0.first })
        // The app ends mid-retry: its delivery stops, and the next launch finds the files as
        // they were.
        running.cancel()
        _ = try? await running.value
        await tracker.finish()
        try FileManager.default.copyItem(atPath: directory.string, toPath: relaunched.string)
        let expectedBody = firstBody.replacingOccurrences(of: "false", with: "true")
        let expectedPending = 0

        let next = try SegmentStore(events: [Tapped.self], directory: relaunched)
        let nextTracker = Tracker(store: next)
        let online = ScriptedTransport([.success(HTTPResponse(status: .ok))])
        await nextTracker.finish()
        try await nextTracker.records.batch(strategy: .count(2))
            .deliver(to: HTTPDestination(endpoint: endpoint, transport: online, encoder: IdentifiersEncoder(), clock: clock))
            .execute()

        let actual = online.bodies.withLock { $0 }
        #expect(actual == [expectedBody])
        #expect(next.pendingRecordCount == expectedPending)
    }
}

extension HTTPDestinationStoreTests.Tapped: Codable {}
