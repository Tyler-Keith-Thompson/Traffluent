import DestinationTesting
import Destinations
import Events
import Foundation
import Persistence
import Testing
import Trackers

@Suite("RecordStore: sensitive values", .timeLimit(.minutes(1)))
struct RecordStoreSensitiveTests {
    struct SignedUp: Event {
        var email: Sensitive<String>
    }

    @Test("A record recovered after a relaunch reveals its sensitive values to a destination, unless redacted", arguments: StoreKind.all)
    func recoveredReveals(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [SignedUp.self]).store
        let earlier = Tracker(store: first)
        earlier.track(SignedUp(email: Sensitive("ada@example.com")))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [SignedUp.self]).store
        let revealing = InMemoryDestination()
        let redacted = InMemoryDestination()
        let expected = "ada@example.com"

        let sut = Tracker(store: next)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: revealing, redacted.redactingSensitiveValues()).execute()

        let revealingRecord = try #require(revealing.records.first)
        let redactedRecord = try #require(redacted.records.first)
        let event = try #require(revealingRecord.event as? SignedUp)
        #expect(revealingRecord.reveal(event.email) == expected)
        #expect(redactedRecord.reveal(event.email) == nil)
    }
}

extension RecordStoreSensitiveTests.SignedUp: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(email)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        email = try decoder.decode()
    }
}
