import DestinationTesting
import Destinations
import Events
import Foundation
import Synchronization
import Testing
import Trackers

@Suite("Consent", .timeLimit(.minutes(1)))
struct ConsentTests {
    struct Viewed: Event {
        var number: Int
    }

    struct AdClicked: Event {
        static let consentCategory = ConsentCategory.advertising
        var number: Int
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

    @Test("A category not given a status is undecided")
    func undecidedByDefault() {
        let sut = Consent()

        let actual = sut.status(of: .analytics)

        #expect(actual == .undecided)
    }

    @Test("A consent starts with the statuses it is given, every other category undecided")
    func initialStatuses() {
        let sut = Consent([.analytics: .granted, .advertising: .denied])

        #expect(sut.status(of: .analytics) == .granted)
        #expect(sut.status(of: .advertising) == .denied)
        #expect(sut.status(of: .functional) == .undecided)
    }

    @Test("Granting and denying set only the categories named, and a later decision replaces an earlier one")
    func decisions() {
        let sut = Consent()

        sut.grant(.analytics, .functional)
        sut.deny(.advertising)
        sut.deny(.functional)

        #expect(sut.status(of: .analytics) == .granted)
        #expect(sut.status(of: .advertising) == .denied)
        #expect(sut.status(of: .functional) == .denied)
        #expect(sut.status(of: .personalization) == .undecided)
    }

    @Test("Copies of a consent share their decisions")
    func copiesShare() {
        let sut = Consent()
        let copy = sut

        copy.grant(.analytics)

        #expect(sut.status(of: .analytics) == .granted)
    }

    @Test("An event whose category is granted is delivered")
    func grantedDelivered() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent([.analytics: .granted])
        let sut = Tracker(consent: consent)
        let expected = [1]

        sut.track(Viewed(number: 1))
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
        #expect(consent.heldRecordCount == 0)
    }

    @Test("An event whose category is denied never reaches a destination, and isn't reported")
    func deniedNeverDelivered() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent([.analytics: .granted, .advertising: .denied])
        let sut = Tracker(consent: consent)
        let expected = [1, 3]

        sut.track(Viewed(number: 1))
        sut.track(AdClicked(number: 2))
        sut.track(Viewed(number: 3))
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
        #expect(consent.heldRecordCount == 0)
    }

    @Test("Events of an undecided category are held, not delivered, until it is decided")
    func undecidedHeld() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let sut = Tracker(consent: consent)
        let expected: [Int] = []

        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))
        await sut.flush()
        let actualHeld = consent.heldRecordCount
        consent.deny(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(5)).deliver(to: recorder).execute()

        #expect(actualHeld == 2)
        #expect(recorder.numbers == expected)
    }

    @Test("Held while undecided, delivered in order on grant, then later events after them")
    func heldThenGranted() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let sut = Tracker(consent: consent)
        let expected = [1, 2, 3, 4]
        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))
        sut.track(Viewed(number: 3))

        consent.grant(.analytics)
        sut.track(Viewed(number: 4))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
        #expect(consent.heldRecordCount == 0)
    }

    @Test("Held while undecided, dropped on deny with a report of how many and when, and later events not collected")
    func heldThenDenied() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let ticker = Ticker()
        let sut = Tracker(consent: consent, now: ticker.now)
        let expectedReport = ConsentDropReport.denied(
            category: .analytics, recordCount: 2,
            timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 2))
        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))

        consent.deny(.analytics)
        sut.track(Viewed(number: 3))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        var reports = consent.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(recorder.numbers.isEmpty)
        #expect(consent.heldRecordCount == 0)
    }

    @Test("A decision releases only its own categories; the others stay held")
    func decisionPerCategory() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let sut = Tracker(consent: consent)
        let expected = [1, 3]
        sut.track(Viewed(number: 1))
        sut.track(AdClicked(number: 2))
        sut.track(Viewed(number: 3))

        consent.grant(.analytics)
        await sut.flush()
        let actualHeld = consent.heldRecordCount
        consent.deny(.advertising)
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(actualHeld == 1)
        #expect(recorder.numbers == expected)
    }

    @Test("A denial reports each category it drops on its own")
    func deniedReportPerCategory() async {
        let consent = Consent()
        let ticker = Ticker()
        let sut = Tracker(consent: consent, now: ticker.now)
        let expected: [ConsentDropReport] = [
            .denied(category: .advertising, recordCount: 1, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 1)),
            .denied(category: .analytics, recordCount: 2, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 3)),
        ]
        sut.track(AdClicked(number: 1))
        sut.track(Viewed(number: 2))
        sut.track(Viewed(number: 3))

        consent.deny(.analytics, .advertising)

        var reports = consent.dropReports.makeAsyncIterator()
        var actual: [ConsentDropReport] = []
        for _ in expected {
            actual += await reports.next().map { [$0] } ?? []
        }
        #expect(actual == expected)
        await sut.finish()
    }

    @Test("Denying a category with nothing held reports nothing")
    func denyNothingHeld() async {
        let consent = Consent()
        let sut = Tracker(consent: consent, now: { Date(timeIntervalSince1970: 5) })
        // Finishing with one record held reports it, so it is the first report only if the
        // denial reported nothing.
        let expected = ConsentDropReport.finishedUndecided(
            recordCount: 1, timestamps: Date(timeIntervalSince1970: 5) ... Date(timeIntervalSince1970: 5))
        sut.track(Viewed(number: 1))

        consent.deny(.advertising)
        await sut.finish()

        var reports = consent.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
    }

    @Test("A grant after a denial lets later events through; the denied ones stay dropped")
    func grantAfterDeny() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent([.analytics: .denied])
        let sut = Tracker(consent: consent)
        let expected = [2]

        sut.track(Viewed(number: 1))
        consent.grant(.analytics)
        sut.track(Viewed(number: 2))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A denial after a grant drops later events; those already let through are still delivered")
    func denyAfterGrant() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent([.analytics: .granted])
        let sut = Tracker(consent: consent)
        let expected = [1]

        sut.track(Viewed(number: 1))
        consent.deny(.analytics)
        sut.track(Viewed(number: 2))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("When the hold is full its oldest record is dropped, and a grant delivers the rest")
    func holdBound() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent(heldRecordLimit: 2)
        let sut = Tracker(consent: consent)
        let expected = [3, 4]
        for number in 1 ... 4 {
            sut.track(Viewed(number: number))
        }
        await sut.flush()
        let actualHeld = consent.heldRecordCount

        consent.grant(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(actualHeld == 2)
        #expect(recorder.numbers == expected)
    }

    @Test("A record dropped for room is reported as it is dropped, while the category is still undecided")
    func overflowReportedAtOnce() async {
        let consent = Consent(heldRecordLimit: 2)
        let ticker = Ticker()
        let sut = Tracker(consent: consent, now: ticker.now)
        let expected = ConsentDropReport.heldRecordLimit(
            recordCount: 1, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 1))
        var reports = consent.dropReports.makeAsyncIterator()
        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))
        sut.track(Viewed(number: 3))

        let actual = await reports.next()

        #expect(actual == expected)
        #expect(consent.status(of: .analytics) == .undecided)
        await sut.finish()
    }

    @Test("Overflow reports no one has read merge into one: many records dropped for room wait as one report counting them all")
    func overflowReportsMerge() async {
        let consent = Consent(heldRecordLimit: 1)
        let ticker = Ticker()
        let sut = Tracker(consent: consent, now: ticker.now)
        let expected: [ConsentDropReport] = [
            .heldRecordLimit(recordCount: 499, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 499)),
            .finishedUndecided(recordCount: 1, timestamps: Date(timeIntervalSince1970: 500) ... Date(timeIntervalSince1970: 500)),
        ]
        for number in 1 ... 500 {
            sut.track(Viewed(number: number))
        }

        await sut.finish()
        var reports = consent.dropReports.makeAsyncIterator()
        let actual = [await reports.next(), await reports.next()]

        #expect(actual == expected)
    }

    @Test("Overflow reports merge only with the one waiting right before them, so they stay in order with denials")
    func overflowMergesInOrder() async {
        let consent = Consent(heldRecordLimit: 1)
        let ticker = Ticker()
        let sut = Tracker(consent: consent, now: ticker.now)
        let expected: [ConsentDropReport] = [
            .heldRecordLimit(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 1)),
            .denied(category: .advertising, recordCount: 1, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 2)),
            .heldRecordLimit(recordCount: 2, timestamps: Date(timeIntervalSince1970: 3) ... Date(timeIntervalSince1970: 4)),
        ]
        sut.track(Viewed(number: 1))
        sut.track(AdClicked(number: 2))
        consent.deny(.advertising)
        sut.track(Viewed(number: 3))
        sut.track(Viewed(number: 4))
        sut.track(Viewed(number: 5))

        await sut.flush()
        var reports = consent.dropReports.makeAsyncIterator()
        let actual = [await reports.next(), await reports.next(), await reports.next()]

        #expect(actual == expected)
        await sut.finish()
    }

    @Test("The hold's bound is across categories: the oldest record of any is dropped first")
    func holdBoundAcrossCategories() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent(heldRecordLimit: 2)
        let sut = Tracker(consent: consent)
        let expected = [2, 3]
        sut.track(AdClicked(number: 1))
        sut.track(Viewed(number: 2))
        sut.track(AdClicked(number: 3))

        consent.grant(.analytics, .advertising)
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("By default the hold keeps 1,000 records")
    func defaultHoldBound() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let sut = Tracker(consent: consent)
        let expected = Array(2 ... 1_001)

        for number in 1 ... 1_001 {
            sut.track(Viewed(number: number))
        }
        await sut.flush()
        let actualHeld = consent.heldRecordCount
        consent.grant(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(2_000)).deliver(to: recorder).execute()

        #expect(Consent.defaultHeldRecordLimit == 1_000)
        #expect(actualHeld == 1_000)
        #expect(recorder.numbers == expected)
    }

    @Test("A hold of 0 drops every undecided event, reported")
    func zeroHold() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent(heldRecordLimit: 0)
        let ticker = Ticker()
        let sut = Tracker(consent: consent, now: ticker.now)
        // Read after the tracker finished, so the two drops wait, merged, as one report.
        let expectedReports: [ConsentDropReport] = [
            .heldRecordLimit(recordCount: 2, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 2)),
        ]
        let expected = [3]
        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))

        consent.grant(.analytics)
        sut.track(Viewed(number: 3))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        var reports = consent.dropReports.makeAsyncIterator()
        let actualReports = [await reports.next()]
        #expect(actualReports == expectedReports)
        #expect(recorder.numbers == expected)
    }

    @Test("Finishing a tracker drops what it holds in memory only, reported, and a later grant delivers none of it")
    func finishWhileUndecided() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let ticker = Ticker()
        let sut = Tracker(consent: consent, now: ticker.now)
        let expectedReport = ConsentDropReport.finishedUndecided(
            recordCount: 2, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 2))
        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))

        await sut.finish()
        consent.grant(.analytics)
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        var reports = consent.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
        #expect(consent.heldRecordCount == 0)
        #expect(recorder.numbers.isEmpty)
    }

    @Test("Finishing one tracker leaves another tracker's held records in a shared consent")
    func finishIsPerTracker() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let finished = Tracker(consent: consent)
        let sut = Tracker(consent: consent)
        let expected = [2]
        finished.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))
        await sut.flush()

        await finished.finish()
        consent.grant(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("A grant delivers each tracker's held records to that tracker's records, not another's sharing the consent")
    func grantPerTracker() async throws {
        let consent = Consent()
        let first = Tracker(consent: consent)
        let second = Tracker(consent: consent)
        let firstRecorder = InMemoryDestination()
        let secondRecorder = InMemoryDestination()
        first.track(Viewed(number: 1))
        second.track(Viewed(number: 2))
        await first.flush()
        await second.flush()

        consent.grant(.analytics)
        await first.finish()
        await second.finish()
        try await first.records.batch(strategy: .count(10)).deliver(to: firstRecorder).execute()
        try await second.records.batch(strategy: .count(10)).deliver(to: secondRecorder).execute()

        #expect(firstRecorder.numbers == [1])
        #expect(secondRecorder.numbers == [2])
    }

    @Test("An overflow drop is reported before a later denial's")
    func overflowReportedFirst() async {
        let consent = Consent(heldRecordLimit: 1)
        let ticker = Ticker()
        let sut = Tracker(consent: consent, now: ticker.now)
        let expected: [ConsentDropReport] = [
            .heldRecordLimit(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 1)),
            .denied(category: .analytics, recordCount: 1, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 2)),
        ]
        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))

        consent.deny(.analytics)

        var reports = consent.dropReports.makeAsyncIterator()
        var actual: [ConsentDropReport] = []
        for _ in expected {
            actual += await reports.next().map { [$0] } ?? []
        }
        #expect(actual == expected)
        await sut.finish()
    }

    @Test("An event tracked after finish is dropped, not held, so a later grant can't send it to the finished tracker")
    func trackAfterFinish() async throws {
        let consent = Consent()
        let sut = Tracker(consent: consent)
        await sut.finish()

        sut.track(Viewed(number: 1))
        consent.grant(.analytics)
        let actual = await sut.records.reduce(0) { count, _ in count + 1 }

        #expect(consent.heldRecordCount == 0)
        #expect(actual == 0)
    }

    @Test("A tracker whose every copy is released ends its records, and drops what it held in memory only, reported")
    func releasedWithoutFinish() async {
        let consent = Consent()
        let ticker = Ticker()
        let expected = ConsentDropReport.finishedUndecided(
            recordCount: 1, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 1))
        var records = makeTracker(consent: consent, now: ticker.now).makeAsyncIterator()
        var reports = consent.dropReports.makeAsyncIterator()

        let actual = await reports.next()
        let next = await records.next()

        #expect(actual == expected)
        #expect(next == nil)
        #expect(consent.heldRecordCount == 0)

        /// A tracker's records once it has tracked one event and its every copy is gone.
        func makeTracker(consent: Consent, now: @escaping @Sendable () -> Date) -> Tracker.Records {
            let tracker = Tracker(consent: consent, now: now)
            tracker.track(Viewed(number: 1))
            return tracker.records
        }
    }

    @Test("The checked spelling makes a consent holding up to the limit it is given")
    func checkedLimit() async throws {
        let consent = try Consent(checkedHeldRecordLimit: 1)
        let sut = Tracker(consent: consent)
        let expected = 1
        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))

        await sut.flush()

        #expect(consent.heldRecordCount == expected)
        await sut.finish()
    }

    @Test("The checked spelling accepts a limit of 0")
    func checkedZeroLimit() throws {
        let sut = try Consent([.analytics: .granted], checkedHeldRecordLimit: 0)

        #expect(sut.status(of: .analytics) == .granted)
    }

    @Test("The checked spelling throws NegativeHeldRecordLimit for a negative limit", arguments: [-1, Int.min])
    func checkedNegativeLimit(limit: Int) {
        let expected = NegativeHeldRecordLimit()

        #expect(throws: expected) {
            _ = try Consent(checkedHeldRecordLimit: limit)
        }
    }

    @Test("A report's timestamps span the earliest and latest dropped, whatever order they were tracked in")
    func timestampsSpanOutOfOrder() async {
        let consent = Consent()
        let times = Mutex([5.0, 9.0, 2.0])
        let sut = Tracker(consent: consent, now: { Date(timeIntervalSince1970: times.withLock { $0.removeFirst() }) })
        let expected = ConsentDropReport.denied(
            category: .analytics, recordCount: 3, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 9))
        for number in 1 ... 3 {
            sut.track(Viewed(number: number))
        }

        consent.deny(.analytics)

        var reports = consent.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        await sut.finish()
    }

    @Test("A held record keeps its timestamp, call site and context when it is delivered on grant")
    func heldRecordUnchanged() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let sut = Tracker(consent: consent, now: { Date(timeIntervalSince1970: 3) })
        let expectedLocation = Events.SourceLocation(file: "App/Cart.swift", fileID: "App/Cart.swift", function: "pay()", line: 41, column: 7)
        sut.track(Viewed(number: 1), file: "App/Cart.swift", fileID: "App/Cart.swift", function: "pay()", line: 41, column: 7)

        consent.grant(.analytics)
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        let actual = try #require(recorder.records.first)
        #expect(actual.timestamp == Date(timeIntervalSince1970: 3))
        #expect(actual.sourceLocation == expectedLocation)
        #expect(actual.revealsSensitiveValues)
    }

    @Test("A grant releases held records to a delivery already running")
    func grantWhileDelivering() async throws {
        let recorder = InMemoryDestination()
        let consent = Consent()
        let sut = Tracker(consent: consent)
        let expected = [1, 2]
        let delivery = Task { try await sut.records.batch(strategy: .count(2)).deliver(to: recorder).execute() }
        sut.track(Viewed(number: 1))
        sut.track(Viewed(number: 2))

        consent.grant(.analytics)
        var deliveries = recorder.deliveries.makeAsyncIterator()
        _ = await deliveries.next()
        let actual = recorder.numbers
        await sut.finish()
        try await delivery.value

        #expect(actual == expected)
    }

    @Test("A tracker given no consent delivers every category")
    func noConsent() async throws {
        let recorder = InMemoryDestination()
        let sut = Tracker()
        let expected = [1, 2]

        sut.track(Viewed(number: 1))
        sut.track(AdClicked(number: 2))
        await sut.finish()
        try await sut.records.batch(strategy: .count(10)).deliver(to: recorder).execute()

        #expect(recorder.numbers == expected)
    }

    @Test("The drop reports end once the consent is gone")
    func reportsEnd() async {
        var reports = Consent().dropReports.makeAsyncIterator()

        let actual = await reports.next()

        #expect(actual == nil)
    }
}

extension InMemoryDestination {
    /// The numbers of the events received, in the order received.
    fileprivate var numbers: [Int] {
        records.compactMap { record in
            switch record.event {
            case let event as ConsentTests.Viewed: event.number
            case let event as ConsentTests.AdClicked: event.number
            default: nil
            }
        }
    }
}
