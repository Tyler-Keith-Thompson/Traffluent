import Destinations
import Events
import Instrumentation
import Synchronization
import Testing
import Trackers

@Suite("enriched(by:)", .timeLimit(.minutes(1)))
struct EnrichedTests {
    struct Tapped: Event {
        var number: Int
    }

    struct AdClicked: Event {
        static let consentCategory = ConsentCategory.advertising
        var number: Int
    }

    struct Marker: Event {
        var label: String
    }

    enum RegionKey: ServiceContextKey {
        typealias Value = String
    }

    enum TrailKey: ServiceContextKey {
        typealias Value = String
    }

    enum AccountKey: ServiceContextKey {
        typealias Value = Sensitive<String>
    }

    final class Calls: Sendable {
        let count = Atomic<Int>(0)
    }

    @Test("Each record an enriched destination receives carries what the enricher sets; a sibling fed the same batches doesn't")
    func enrichedAndSibling() async throws {
        let enriched = InMemoryDestination()
        let sibling = InMemoryDestination()
        let tracker = Tracker()
        let sut = enriched.enriched(by: Enricher { $0[RegionKey.self] = "eu-west" })
        let expectedEnriched: [String?] = ["eu-west", "eu-west", "eu-west"]
        let expectedSibling: [String?] = [nil, nil, nil]

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        tracker.track(Tapped(number: 3))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(2)).deliver(to: sut, sibling).execute()

        let actualEnriched = enriched.records.map { $0.context[RegionKey.self] }
        let actualSibling = sibling.records.map { $0.context[RegionKey.self] }
        #expect(actualEnriched == expectedEnriched)
        #expect(actualSibling == expectedSibling)
        #expect(enriched.records.map(\.id) == sibling.records.map(\.id))
        #expect(enriched.batches.map(\.count) == [2, 1])
    }

    @Test("A destination's enricher runs after the tracker's, overriding its value at that destination alone")
    func overridesTrackersValue() async throws {
        let enriched = InMemoryDestination()
        let sibling = InMemoryDestination()
        let tracker = Tracker(enrichers: [Enricher { $0[RegionKey.self] = "us-east"; $0[TrailKey.self] = "tracker" }])
        let sut = enriched.enriched(by: Enricher { $0[RegionKey.self] = "eu-west" })
        let expectedEnrichedRegion = "eu-west"
        let expectedSiblingRegion = "us-east"
        let expectedTrail = "tracker"

        tracker.track(Tapped(number: 1))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut, sibling).execute()

        let enrichedRecord = try #require(enriched.records.first)
        let siblingRecord = try #require(sibling.records.first)
        #expect(enrichedRecord.context[RegionKey.self] == expectedEnrichedRegion)
        #expect(enrichedRecord.context[TrailKey.self] == expectedTrail)
        #expect(siblingRecord.context[RegionKey.self] == expectedSiblingRegion)
    }

    @Test("An enricher that sets nothing hands the destination each record as tracked")
    func setsNothing() async throws {
        let enriched = InMemoryDestination()
        let sibling = InMemoryDestination()
        let tracker = Tracker(enrichers: [Enricher { $0[TrailKey.self] = "tracker" }])
        let sut = enriched.enriched(by: Enricher { _ in })
        let expectedNumbers = [1, 2]
        let expectedTrails: [String?] = ["tracker", "tracker"]

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(2)).deliver(to: sut, sibling).execute()

        #expect(enriched.events(of: Tapped.self).map(\.number) == expectedNumbers)
        #expect(enriched.records.map(\.id) == sibling.records.map(\.id))
        #expect(enriched.records.map(\.timestamp) == sibling.records.map(\.timestamp))
        #expect(enriched.records.map(\.sourceLocation) == sibling.records.map(\.sourceLocation))
        #expect(enriched.records.map { $0.context[TrailKey.self] } == expectedTrails)
        let revealing = enriched.records.allSatisfy(\.revealsSensitiveValues)
        #expect(revealing)
    }

    @Test("An empty batch reaches neither the enricher nor the destination")
    func emptyBatch() async {
        let recorder = InMemoryDestination()
        let calls = Calls()
        let sut = recorder.enriched(by: Enricher { _ in calls.count.add(1, ordering: .relaxed) })
        let expectedCalls = 0

        await sut.receive([])

        #expect(recorder.batches.isEmpty)
        #expect(calls.count.load(ordering: .relaxed) == expectedCalls)
    }

    @Test("The enricher runs once on each record of a batch")
    func oncePerRecord() async throws {
        let recorder = InMemoryDestination()
        let calls = Calls()
        let tracker = Tracker()
        let sut = recorder.enriched(by: Enricher { _ in calls.count.add(1, ordering: .relaxed) })
        let expectedCalls = 3

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        tracker.track(Tapped(number: 3))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(3)).deliver(to: sut).execute()

        #expect(calls.count.load(ordering: .relaxed) == expectedCalls)
    }

    @Test("Records the enricher adds are left out; the destination receives the tracked records, enriched")
    func addedRecordsLeftOut() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let adding = Enricher(records: { record in
            record.context[RegionKey.self] = "eu-west"
            return [EventRecord(event: Marker(label: "added"), timestamp: record.timestamp, sourceLocation: nil)]
        })
        let sut = recorder.enriched(by: adding)
        let expectedNames = ["Tapped", "Tapped"]
        let expectedRegions: [String?] = ["eu-west", "eu-west"]

        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(2)).deliver(to: sut).execute()

        #expect(recorder.records.map(\.name) == expectedNames)
        #expect(recorder.records.map { $0.context[RegionKey.self] } == expectedRegions)
    }

    @Test("Enriched twice, the enricher applied last runs first, so the one applied first sets a key last")
    func enrichedTwice() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let first = Enricher { $0[RegionKey.self] = "first"; $0[TrailKey.self] = ($0[TrailKey.self] ?? "") + "first," }
        let second = Enricher { $0[RegionKey.self] = "second"; $0[TrailKey.self] = ($0[TrailKey.self] ?? "") + "second," }
        let sut = recorder.enriched(by: first).enriched(by: second)
        let expectedRegion = "first"
        let expectedTrail = "second,first,"

        tracker.track(Tapped(number: 1))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(to: sut).execute()

        let record = try #require(recorder.records.first)
        #expect(record.context[RegionKey.self] == expectedRegion)
        #expect(record.context[TrailKey.self] == expectedTrail)
    }

    @Test("A sensitive value an enricher sets stays hidden from a redacting destination, whichever modifier is applied first")
    func withRedaction() async throws {
        let enrichedFirst = InMemoryDestination()
        let redactedFirst = InMemoryDestination()
        let revealing = InMemoryDestination()
        let account = Enricher { $0[AccountKey.self] = Sensitive("account-42") }
        let tracker = Tracker()
        let expected = "account-42"

        tracker.track(Tapped(number: 1))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(
            to: enrichedFirst.enriched(by: account).redactingSensitiveValues(),
            redactedFirst.redactingSensitiveValues().enriched(by: account),
            revealing.enriched(by: account)
        ).execute()

        let enrichedFirstRecord = try #require(enrichedFirst.records.first)
        let redactedFirstRecord = try #require(redactedFirst.records.first)
        let revealingRecord = try #require(revealing.records.first)
        let enrichedFirstValue = try #require(enrichedFirstRecord.context[AccountKey.self])
        let redactedFirstValue = try #require(redactedFirstRecord.context[AccountKey.self])
        let revealingValue = try #require(revealingRecord.context[AccountKey.self])
        #expect(enrichedFirstRecord.reveal(enrichedFirstValue) == nil)
        #expect(redactedFirstRecord.reveal(redactedFirstValue) == nil)
        #expect(revealingRecord.reveal(revealingValue) == expected)
    }

    @Test("Inside accepting(_:), the enricher runs on the accepted records alone; outside it, on every record; the destination receives the same either way")
    func withAccepting() async throws {
        let enrichedInside = InMemoryDestination()
        let enrichedOutside = InMemoryDestination()
        let insideCalls = Calls()
        let outsideCalls = Calls()
        let tracker = Tracker()
        let expectedInsideCalls = 2
        let expectedOutsideCalls = 3
        let expectedNumbers = [1, 3]
        let expectedRegions: [String?] = ["eu-west", "eu-west"]

        tracker.track(Tapped(number: 1))
        tracker.track(AdClicked(number: 2))
        tracker.track(Tapped(number: 3))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(3)).deliver(
            to: enrichedInside.enriched(by: Enricher { insideCalls.count.add(1, ordering: .relaxed); $0[RegionKey.self] = "eu-west" }).accepting(.analytics),
            enrichedOutside.accepting(.analytics).enriched(by: Enricher { outsideCalls.count.add(1, ordering: .relaxed); $0[RegionKey.self] = "eu-west" })
        ).execute()

        #expect(insideCalls.count.load(ordering: .relaxed) == expectedInsideCalls)
        #expect(outsideCalls.count.load(ordering: .relaxed) == expectedOutsideCalls)
        #expect(enrichedInside.events(of: Tapped.self).map(\.number) == expectedNumbers)
        #expect(enrichedOutside.events(of: Tapped.self).map(\.number) == expectedNumbers)
        #expect(enrichedInside.records.map { $0.context[RegionKey.self] } == expectedRegions)
        #expect(enrichedOutside.records.map { $0.context[RegionKey.self] } == expectedRegions)
    }

    @Test("A destination enriched with nothing accepted receives no batch, and the enricher never runs")
    func nothingAccepted() async throws {
        let recorder = InMemoryDestination()
        let calls = Calls()
        let tracker = Tracker()
        let expectedCalls = 0

        tracker.track(AdClicked(number: 1))
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(1)).deliver(
            to: recorder.enriched(by: Enricher { _ in calls.count.add(1, ordering: .relaxed) }).accepting(.analytics)
        ).execute()

        #expect(recorder.batches.isEmpty)
        #expect(calls.count.load(ordering: .relaxed) == expectedCalls)
    }
}
