import Events
import Foundation
import Instrumentation
import Testing
import Trackers

@Suite("Tracker: records an enricher adds", .timeLimit(.minutes(1)))
struct AddedRecordsTests {
    struct Tapped: Event {
        var number: Int
    }

    struct Marker: Event {
        var label: String

        func constraintViolation() -> ConstraintViolation? {
            label.isEmpty ? ConstraintViolation(property: "label", keyword: .minLength(1)) : nil
        }
    }

    enum TrailKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Records an enricher adds come before the record, in the order it returns them")
    func addedBefore() async {
        let adding = Enricher(records: { record in
            guard record.event is Tapped else { return [] }
            return [
                EventRecord(event: Marker(label: "first"), timestamp: record.timestamp, sourceLocation: nil),
                EventRecord(event: Marker(label: "second"), timestamp: record.timestamp, sourceLocation: nil),
            ]
        })
        let sut = Tracker(enrichers: [adding])
        let expected = ["Marker(label: \"first\")", "Marker(label: \"second\")", "Tapped(number: 1)"]

        sut.track(Tapped(number: 1))
        await sut.finish()

        var actual: [String] = []
        for await record in sut.records {
            actual.append(String(describing: record.event))
        }
        #expect(actual == expected)
    }

    @Test("The enrichers after the one that adds a record run on it; the ones before it don't run again")
    func addedEnrichedByLaterOnly() async {
        let before = Enricher { $0[TrailKey.self] = ($0[TrailKey.self] ?? "") + "before," }
        let adding = Enricher(records: { record in
            guard record.event is Tapped else { return [] }
            return [EventRecord(event: Marker(label: "added"), timestamp: record.timestamp, sourceLocation: nil, context: record.context)]
        })
        let after = Enricher { $0[TrailKey.self] = ($0[TrailKey.self] ?? "") + "after," }
        let sut = Tracker(enrichers: [before, adding, after])
        let expected = ["before,after,", "before,after,"]

        sut.track(Tapped(number: 1))
        await sut.finish()

        var actual: [String?] = []
        for await record in sut.records {
            actual.append(record.context[TrailKey.self])
        }
        #expect(actual == expected)
    }

    @Test("An enricher of a tracker copy adds records before the tracker's enrichers run on them")
    func addedByCopy() async {
        let adding = Enricher(records: { record in
            guard record.event is Tapped else { return [] }
            return [EventRecord(event: Marker(label: "added"), timestamp: record.timestamp, sourceLocation: nil)]
        })
        let after = Enricher { $0[TrailKey.self] = "tracker" }
        let sut = Tracker(enrichers: [after]).enriched(by: adding)
        let expected: [String?] = ["tracker", "tracker"]

        sut.track(Tapped(number: 1))
        await sut.finish()

        var actual: [String?] = []
        for await record in sut.records {
            actual.append(record.context[TrailKey.self])
        }
        #expect(actual == expected)
    }

    @Test("An added record that breaks a constraint is rejected and reported, and the record it preceded still delivered")
    func addedRejected() async {
        let adding = Enricher(records: { record in
            guard record.event is Tapped else { return [] }
            return [EventRecord(event: Marker(label: ""), timestamp: record.timestamp, sourceLocation: nil)]
        })
        let sut = Tracker(enrichers: [adding])
        let expectedRecords = ["Tapped(number: 1)"]
        let expectedRejections = ["Marker"]

        sut.track(Tapped(number: 1))
        await sut.finish()

        var actualRecords: [String] = []
        for await record in sut.records {
            actualRecords.append(String(describing: record.event))
        }
        var actualRejections: [String] = []
        for await report in sut.rejectionReports {
            actualRejections.append(report.eventName)
        }
        #expect(actualRecords == expectedRecords)
        #expect(actualRejections == expectedRejections)
    }

    @Test("A record an enricher adds reveals its sensitive values, as a tracked one does")
    func addedReveals() async throws {
        let adding = Enricher(records: { record in
            guard record.event is Tapped else { return [] }
            return [EventRecord(event: Marker(label: "added"), timestamp: record.timestamp, sourceLocation: nil)]
        })
        let sut = Tracker(enrichers: [adding])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next())
        #expect(actual.revealsSensitiveValues)
    }
}
