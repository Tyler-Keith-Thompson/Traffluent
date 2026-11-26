import Events
import Foundation
import Instrumentation
import Testing

@Suite("Enricher")
struct EnricherTests {
    struct Tapped: Event {
        var number: Int
    }

    enum RegionKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("A context enricher sets its values on the record's context, adds no records and says it adds none")
    func contextEnricher() {
        let sut = Enricher { $0[RegionKey.self] = "eu-west" }
        var record = EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = "eu-west"

        let added = sut(&record)

        #expect(record.context[RegionKey.self] == expected)
        #expect(added.isEmpty)
        #expect(!sut.addsRecords)
    }

    @Test("A record enricher changes the record, returns the records it adds and says it adds records")
    func recordEnricher() {
        let sut = Enricher(records: { record in
            record.context[RegionKey.self] = "eu-west"
            return [EventRecord(event: Tapped(number: 0), timestamp: record.timestamp, sourceLocation: nil)]
        })
        var record = EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expectedRegion = "eu-west"
        let expectedAdded = 1

        let added = sut(&record)

        #expect(record.context[RegionKey.self] == expectedRegion)
        #expect(added.count == expectedAdded)
        #expect(sut.addsRecords)
    }
}
