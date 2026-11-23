import Destinations
import Events
import Foundation
import Persistence
import Synchronization
import Testing
import Trackers

@Suite("Tracker: rejections", .timeLimit(.minutes(1)))
struct RejectionTests {
    /// An event whose query must not be empty and whose count must be at most 10.
    struct Searched: Event, Equatable {
        var query: String
        var count: Int

        func constraintViolation() -> ConstraintViolation? {
            let minLength = Constraint<String>.minLength(1)
            if !minLength.isSatisfied(by: query) { return ConstraintViolation(property: "query", keyword: minLength.keyword) }
            let maximum = Constraint<Int>.maximum(10)
            if !maximum.isSatisfied(by: count) { return ConstraintViolation(property: "count", keyword: maximum.keyword) }
            return nil
        }
    }

    struct AdSearched: Event, Equatable {
        static let consentCategory = ConsentCategory.advertising
        var query: String

        func constraintViolation() -> ConstraintViolation? {
            query.isEmpty ? ConstraintViolation(property: "query", keyword: .minLength(1)) : nil
        }
    }

    /// Hands out 1970 plus one second, plus two, and so on: a later date each call.
    final class Ticker: Sendable {
        let calls = Mutex(0)

        func now() -> Date {
            calls.withLock {
                $0 += 1
                return Date(timeIntervalSince1970: Double($0))
            }
        }
    }

    /// A store that keeps nothing and counts its appends.
    final class CountingStore: RecordStore {
        let appended = Mutex(0)

        func append(_ record: EventRecord) -> EventRecord {
            appended.withLock { $0 += 1 }
            return record
        }

        func takeRecoveredRecords() -> [EventRecord] {
            []
        }

        func synchronize() {}
    }

    @Test("A violating event never reaches a destination; the valid ones around it do, in order")
    func rejectedNotDelivered() async throws {
        let sut = Tracker()
        let recorder = InMemoryDestination()
        let expected = [Searched(query: "a", count: 1), Searched(query: "b", count: 2)]

        sut.track(Searched(query: "a", count: 1))
        sut.track(Searched(query: "", count: 1))
        sut.track(Searched(query: "b", count: 2))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.events(of: Searched.self) == expected)
    }

    @Test("A rejection is reported with the event's name, the property, the keyword and when it was tracked")
    func reported() async {
        let ticker = Ticker()
        let sut = Tracker(now: ticker.now)
        let expected = RejectionReport(
            eventName: "Searched",
            violation: ConstraintViolation(property: "count", keyword: .maximum(10)),
            recordCount: 1,
            timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 1)
        )

        sut.track(Searched(query: "a", count: 11))
        await sut.finish()

        var reports = sut.rejectionReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(await reports.next() == nil)
    }

    @Test("A violating event is never written to the store")
    func rejectedNotWritten() async {
        let store = CountingStore()
        let sut = Tracker(store: store)

        sut.track(Searched(query: "", count: 0))
        sut.track(Searched(query: "a", count: 0))
        await sut.finish()

        #expect(store.appended.withLock { $0 } == 1)
    }

    @Test("A violating event of an undecided category is rejected rather than held")
    func rejectedNotHeld() async {
        let consent = Consent()
        let sut = Tracker(consent: consent)

        sut.track(AdSearched(query: ""))
        sut.track(AdSearched(query: "a"))
        await sut.flush()

        #expect(consent.heldRecordCount == 1)
        var reports = sut.rejectionReports.makeAsyncIterator()
        #expect(await reports.next()?.eventName == "AdSearched")
    }

    @Test("A violating event isn't held, so granting its category later never delivers it")
    func rejectedNotReleased() async throws {
        let consent = Consent()
        let sut = Tracker(consent: consent)
        let recorder = InMemoryDestination()
        let expected = [AdSearched(query: "a")]

        sut.track(AdSearched(query: ""))
        sut.track(AdSearched(query: "a"))
        consent.grant(.advertising)
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.events(of: AdSearched.self) == expected)
    }

    @Test("Rejections of one event, property and keyword merge while unread: one report, counting all, across their times")
    func merged() async {
        let ticker = Ticker()
        let sut = Tracker(now: ticker.now)
        let expected = [
            RejectionReport(
                eventName: "Searched", violation: ConstraintViolation(property: "query", keyword: .minLength(1)),
                recordCount: 3, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 5)
            ),
            RejectionReport(
                eventName: "Searched", violation: ConstraintViolation(property: "count", keyword: .maximum(10)),
                recordCount: 1, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 2)
            ),
            RejectionReport(
                eventName: "AdSearched", violation: ConstraintViolation(property: "query", keyword: .minLength(1)),
                recordCount: 1, timestamps: Date(timeIntervalSince1970: 3) ... Date(timeIntervalSince1970: 3)
            ),
        ]

        sut.track(Searched(query: "", count: 0))
        sut.track(Searched(query: "a", count: 11))
        sut.track(AdSearched(query: ""))
        sut.track(Searched(query: "", count: 0))
        sut.track(Searched(query: "", count: 0))
        await sut.finish()

        var actual: [RejectionReport] = []
        for await report in sut.rejectionReports {
            actual.append(report)
        }
        #expect(actual == expected)
    }

    @Test("A merged report's timestamps span the earliest and latest, whatever order the clock gave them")
    func mergedTimestampsOutOfOrder() async {
        let times = Mutex([Date(timeIntervalSince1970: 5), Date(timeIntervalSince1970: 9), Date(timeIntervalSince1970: 2)])
        let sut = Tracker(now: { times.withLock { $0.removeFirst() } })
        let expected = Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 9)

        sut.track(Searched(query: "", count: 0))
        sut.track(Searched(query: "", count: 0))
        sut.track(Searched(query: "", count: 0))
        await sut.finish()

        var reports = sut.rejectionReports.makeAsyncIterator()
        #expect(await reports.next()?.timestamps == expected)
    }

    @Test("A reader waiting for a report gets it as the worker rejects the event")
    func waitingReader() async {
        let sut = Tracker()
        let expected = ConstraintViolation(property: "query", keyword: .minLength(1))
        let reader = Task {
            var reports = sut.rejectionReports.makeAsyncIterator()
            return await reports.next()?.violation
        }

        sut.track(Searched(query: "", count: 0))
        let actual = await reader.value

        #expect(actual == expected)
        await sut.finish()
    }

    @Test("Copies of a tracker share one sequence of reports")
    func copiesShare() async {
        let sut = Tracker()
        let copy = sut

        copy.track(Searched(query: "", count: 0))
        await copy.finish()

        var reports = sut.rejectionReports.makeAsyncIterator()
        #expect(await reports.next()?.recordCount == 1)
    }

    @Test("The reports end once the tracker has finished, and a no-op tracker's are empty")
    func reportsEnd() async {
        let sut = Tracker()
        await sut.finish()

        var reports = sut.rejectionReports.makeAsyncIterator()
        var noOp = Tracker.noOp.rejectionReports.makeAsyncIterator()
        #expect(await reports.next() == nil)
        #expect(await noOp.next() == nil)
    }

    @Test("A report describes the event, the violation and the count")
    func description() {
        let sut = RejectionReport(
            eventName: "Searched", violation: ConstraintViolation(property: "query", keyword: .minLength(1)),
            recordCount: 2, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 2)
        )
        let expected = "Searched: \"query\" breaks minLength 1 (2 rejected)"

        let actual = sut.description

        #expect(actual == expected)
    }
}
