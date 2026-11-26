import Destinations
import Events
import Foundation
import Instrumentation
import Persistence
import Testing
import Trackers

@Suite("RecordStore: enriched destinations", .timeLimit(.minutes(1)))
struct RecordStoreEnrichedTests {
    struct Tapped: Event {
        var number: Int
    }

    enum RegionKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("A record recovered after a relaunch reaches an enriched destination with the enricher's key, though the tracker's context is lost", arguments: StoreKind.all)
    func recoveredEnriched(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let first = try kind.open(at: path, events: [Tapped.self]).store
        let earlier = Tracker(store: first, enrichers: [Enricher { $0[RegionKey.self] = "tracked" }])
        earlier.track(Tapped(number: 1))
        await earlier.finish()
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self]).store
        let enriched = InMemoryDestination()
        let sibling = InMemoryDestination()
        let expectedNumbers = [1]
        let expectedRegion = "eu-west"

        let sut = Tracker(store: next)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(
            to: enriched.enriched(by: Enricher { $0[RegionKey.self] = "eu-west" }),
            sibling
        ).execute()

        let enrichedRecord = try #require(enriched.records.first)
        let siblingRecord = try #require(sibling.records.first)
        #expect(enriched.events(of: Tapped.self).map(\.number) == expectedNumbers)
        #expect(enrichedRecord.context[RegionKey.self] == expectedRegion)
        #expect(siblingRecord.context[RegionKey.self] == nil)
        #expect(enrichedRecord.id == siblingRecord.id)
    }
}

extension RecordStoreEnrichedTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
    }
}
