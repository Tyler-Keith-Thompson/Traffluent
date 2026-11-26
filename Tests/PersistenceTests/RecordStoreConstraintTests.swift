import CBOR
import Destinations
import Events
import Foundation
import Persistence
import Testing
import Trackers

@Suite("RecordStore: constraints", .timeLimit(.minutes(1)))
struct RecordStoreConstraintTests {
    /// The event as an earlier release declared it: no constraint on its count.
    struct Looser: Event, Codable, Equatable {
        static let name = "Tapped"
        var count: Int

        init(count: Int) {
            self.count = count
        }

    }

    /// The same event, of the same name and encoding, as a later release declares it: its count
    /// is at least 0.
    struct Stricter: Event, Codable, Equatable {
        static let name = "Tapped"
        var count: Int

        func constraintViolation() -> ConstraintViolation? {
            count >= 0 ? nil : ConstraintViolation(property: "count", keyword: .minimum(0))
        }

        init(count: Int) {
            self.count = count
        }

    }

    enum Positive: Refinement {
        static var constraints: [Constraint<Int>] {
            get throws(InvalidConstraint) { try [.minimum(1)] }
        }
    }

    @Test("A violating event is never written to the store", arguments: StoreKind.all)
    func rejectedNotWritten(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try kind.open(at: path, events: [Stricter.self]).store
        let tracker = Tracker(store: store)

        tracker.track(Stricter(count: -1))
        tracker.track(Stricter(count: 1))
        await tracker.flush()

        #expect(store.pendingRecordCount == 1)
    }

    @Test("A recovered record that breaks a constraint added since is rejected, reported, and forgotten by the store", arguments: StoreKind.all)
    func recoveredRejected(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Looser.self]).store
        let earlier = Tracker(store: first, now: { Date(timeIntervalSince1970: 4) })
        earlier.track(Looser(count: -1))
        earlier.track(Looser(count: 2))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Stricter.self]).store
        let recorder = InMemoryDestination()
        let expectedReport = RejectionReport(
            eventName: "Tapped",
            violation: ConstraintViolation(property: "count", keyword: .minimum(0)),
            recordCount: 1,
            timestamps: Date(timeIntervalSince1970: 4) ... Date(timeIntervalSince1970: 4)
        )

        let sut = Tracker(store: next)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        var reports = sut.rejectionReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(await reports.next() == nil)
        #expect(recorder.events(of: Stricter.self) == [Stricter(count: 2)])
        #expect(next.pendingRecordCount == 0)
        let third = copy + "-third"
        defer { try? FileManager.default.removeItem(atPath: third) }
        try FileManager.default.copyItem(atPath: copy, toPath: third)
        #expect(try kind.open(at: third, events: [Stricter.self]).store.takeRecoveredRecords().isEmpty)
    }

    @Test("A refined value is written as its value and reads back the same")
    func refinedRoundTrip() throws {
        let expected = try Refined<Int, Positive>(7)
        let expectedBytes = try CBOREncoder().encode(7)

        let bytes = try CBOREncoder().encode(expected)
        let actual = try CBORDecoder().decode(Refined<Int, Positive>.self, from: bytes)

        #expect(actual == expected)
        #expect(bytes == expectedBytes)
    }

    @Test("Decoding a stored value its rule no longer accepts throws dataCorrupted rather than make one")
    func refinedDecodingRejects() throws {
        let bytes = try CBOREncoder().encode(0)

        let error = #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(Refined<Int, Positive>.self, from: bytes)
        }

        guard case .dataCorrupted = error else {
            Issue.record("Expected dataCorrupted, got \(String(describing: error))")
            return
        }
    }

    @Test("Decoding a refined value whose bytes run out throws what reading the value throws")
    func refinedDecodingTruncated() {
        // An unsigned integer's 8-byte head, cut after two of its bytes.
        let bytes: [UInt8] = [0x1B, 0, 1]
        let expected = CBORError.unexpectedEnd(offset: 0)

        #expect(throws: expected) {
            _ = try CBORDecoder().decode(Refined<Int, Positive>.self, from: bytes)
        }
    }
}
