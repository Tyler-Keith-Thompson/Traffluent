import DestinationTesting
import Destinations
import Events
import Foundation
import Instrumentation
import Persistence
import Synchronization
import Testing
import Trackers

@Suite("Tracker: sampling", .timeLimit(.minutes(1)))
struct SamplingTests {
    struct Scrolled: Event, Equatable {
        var number: Int
    }

    struct Tapped: Event, Equatable {
        var number: Int
    }

    struct AdViewed: Event, Equatable {
        static let consentCategory = ConsentCategory.advertising
        var number: Int
    }

    enum CohortKey: ServiceContextKey {
        typealias Value = String
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

    /// A store that keeps nothing and lists the events appended to it.
    final class ListingStore: RecordStore {
        let appended = Mutex<[String]>([])

        func append(_ record: EventRecord) -> EventRecord {
            appended.withLock { $0.append("\(record.event)") }
            return record
        }

        func takeRecoveredRecords() -> [EventRecord] {
            []
        }

        func synchronize() {}
    }

    @Test("With seed 42, an event sampler at 0.5 keeps exactly the pinned events")
    func pinnedEvents() async {
        let sut = Tracker(samplers: [.events(of: Scrolled.self, rate: 0.5)], samplingSeed: 42)
        let expected = [0, 4, 5, 7, 9, 15]

        for number in 0 ..< 16 {
            sut.track(Scrolled(number: number))
        }
        await sut.finish()

        var actual: [Int] = []
        for await record in sut.records {
            if let event = record.event as? Scrolled {
                actual.append(event.number)
            }
        }
        #expect(actual == expected)
    }

    @Test("With seed 42, a grouped sampler at 0.5 keeps exactly the pinned groups, every record of a group alike")
    func pinnedGroups() async {
        let cohorts = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let sut = Tracker(samplers: [.grouped(by: CohortKey.self, rate: 0.5)], samplingSeed: 42)
        let expected = ["c", "f", "h"]
        let expectedDropped = 15

        for round in 0 ..< 3 {
            for name in cohorts {
                var context = ServiceContext.topLevel
                context[CohortKey.self] = name
                ServiceContext.withValue(context) {
                    sut.track(Tapped(number: round))
                }
            }
        }
        await sut.finish()

        var kept: [String: Int] = [:]
        for await record in sut.records {
            kept[record.context[CohortKey.self] ?? "none", default: 0] += 1
        }
        let actual = kept.keys.sorted()
        #expect(actual == expected)
        #expect(kept.values.allSatisfy { $0 == 3 })
        var reports = sut.samplingDropReports.makeAsyncIterator()
        #expect(await reports.next()?.recordCount == expectedDropped)
    }

    @Test("A sampler at rate 0 keeps none of its events, each reported")
    func rateZero() async {
        let sut = Tracker(samplers: [.events(of: Scrolled.self, rate: 0)], samplingSeed: 1)
        let expectedCount = 0
        let expectedDropped = 20

        for number in 0 ..< 20 {
            sut.track(Scrolled(number: number))
        }
        await sut.finish()

        var actual = 0
        for await _ in sut.records {
            actual += 1
        }
        #expect(actual == expectedCount)
        var reports = sut.samplingDropReports.makeAsyncIterator()
        #expect(await reports.next()?.recordCount == expectedDropped)
    }

    @Test("A sampler at rate 1 keeps every one of its events, each carrying rate 1")
    func rateOne() async {
        let sut = Tracker(samplers: [.events(of: Scrolled.self, rate: 1)], samplingSeed: 1)
        let expected = Array(0 ..< 20)
        let expectedRate: SampleRate = 1

        for number in 0 ..< 20 {
            sut.track(Scrolled(number: number))
        }
        await sut.finish()

        var actual: [Int] = []
        var rates: [SampleRate?] = []
        for await record in sut.records {
            actual.append((record.event as? Scrolled)?.number ?? -1)
            rates.append(record.context[SampleRateKey.self])
        }
        #expect(actual == expected)
        #expect(rates.allSatisfy { $0 == expectedRate })
        var reports = sut.samplingDropReports.makeAsyncIterator()
        #expect(await reports.next() == nil)
    }

    @Test("A kept record carries its sampler's rate; an event no sampler applies to is kept and carries no rate")
    func rateCarried() async {
        let sut = Tracker(samplers: [.events(of: Scrolled.self, rate: 0.5)], samplingSeed: 3)
        let expectedRate: SampleRate = 0.5

        for number in 0 ..< 10 {
            sut.track(Scrolled(number: number))
            sut.track(Tapped(number: number))
        }
        await sut.finish()

        var tapped: [Int] = []
        var scrolledRates: [SampleRate?] = []
        var tappedRates: [SampleRate?] = []
        for await record in sut.records {
            if let event = record.event as? Tapped {
                tapped.append(event.number)
                tappedRates.append(record.context[SampleRateKey.self])
            } else {
                scrolledRates.append(record.context[SampleRateKey.self])
            }
        }
        #expect(tapped == Array(0 ..< 10))
        #expect(tappedRates.allSatisfy { $0 == nil })
        #expect(!scrolledRates.isEmpty)
        #expect(scrolledRates.allSatisfy { $0 == expectedRate })
    }

    @Test("A record two samplers keep carries the product of their rates; one either drops is dropped")
    func ratesMultiply() async {
        let sut = Tracker(
            samplers: [.events(of: Scrolled.self, rate: 0.5), .events(where: { $0.event is Scrolled }, rate: 0.5)],
            samplingSeed: 5
        )
        let expectedRate: SampleRate = 0.25

        for number in 0 ..< 200 {
            sut.track(Scrolled(number: number))
        }
        await sut.finish()

        var rates: [SampleRate?] = []
        for await record in sut.records {
            rates.append(record.context[SampleRateKey.self])
        }
        // About a quarter: far below what either sampler alone keeps, about half.
        #expect(rates.count < 80)
        #expect(rates.count > 20)
        #expect(rates.allSatisfy { $0 == expectedRate })
    }

    @Test("Appending a sampler changes no decision of the samplers before it")
    func samplersIndependent() async {
        func kept(_ samplers: [Sampler]) async -> [Int] {
            let tracker = Tracker(samplers: samplers, samplingSeed: 9)
            for number in 0 ..< 64 {
                tracker.track(Scrolled(number: number))
                tracker.track(Tapped(number: number))
            }
            await tracker.finish()
            var numbers: [Int] = []
            for await record in tracker.records {
                if let event = record.event as? Scrolled {
                    numbers.append(event.number)
                }
            }
            return numbers
        }
        let expected = await kept([.events(of: Scrolled.self, rate: 0.5)])

        let actual = await kept([.events(of: Scrolled.self, rate: 0.5), .events(of: Tapped.self, rate: 0.5)])

        #expect(actual == expected)
    }

    @Test("A predicate sampler sees the context the enrichers set")
    func predicateSeesEnrichedContext() async {
        let cohort = Enricher { $0[CohortKey.self] = "beta" }
        let sut = Tracker(enrichers: [cohort], samplers: [.events(where: { $0.context[CohortKey.self] == "beta" }, rate: 0)], samplingSeed: 1)
        let expectedCount = 0

        sut.track(Tapped(number: 0))
        await sut.finish()

        var actual = 0
        for await _ in sut.records {
            actual += 1
        }
        #expect(actual == expectedCount)
    }

    @Test("A grouped sampler leaves a record with no value of its key alone")
    func ungroupedKept() async {
        let sut = Tracker(samplers: [.grouped(by: CohortKey.self, rate: 0)], samplingSeed: 1)
        let expected = [Tapped(number: 0)]

        sut.track(Tapped(number: 0))
        await sut.finish()

        var actual: [Tapped] = []
        var rates: [SampleRate?] = []
        for await record in sut.records {
            actual.append(record.event as? Tapped ?? Tapped(number: -1))
            rates.append(record.context[SampleRateKey.self])
        }
        #expect(actual == expected)
        #expect(rates == [nil])
    }

    @Test("A sampled-out event is never written to the store; the kept ones are")
    func sampledOutNotWritten() async {
        let store = ListingStore()
        let sut = Tracker(store: store, samplers: [.events(of: Scrolled.self, rate: 0)], samplingSeed: 1)
        let expected = ["Tapped(number: 1)"]

        sut.track(Scrolled(number: 0))
        sut.track(Tapped(number: 1))
        sut.track(Scrolled(number: 2))
        await sut.finish()

        let actual = store.appended.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("A sampled-out event of an undecided category is dropped rather than held")
    func sampledOutNotHeld() async {
        let consent = Consent()
        let sut = Tracker(consent: consent, samplers: [.events(of: AdViewed.self, rate: 0)], samplingSeed: 1)
        let expected = 0

        sut.track(AdViewed(number: 0))
        await sut.flush()

        #expect(consent.heldRecordCount == expected)
    }

    @Test("Drops of one event merge while unread: one report per event, counting all, across their times")
    func dropsReported() async {
        let ticker = Ticker()
        let sut = Tracker(samplers: [.events(where: { _ in true }, rate: 0)], samplingSeed: 1, now: ticker.now)
        let expected = [
            SamplingDropReport(eventName: "Scrolled", recordCount: 2, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 3)),
            SamplingDropReport(eventName: "Tapped", recordCount: 1, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 2)),
        ]

        sut.track(Scrolled(number: 0))
        sut.track(Tapped(number: 1))
        sut.track(Scrolled(number: 2))
        await sut.finish()

        var actual: [SamplingDropReport] = []
        for await report in sut.samplingDropReports {
            actual.append(report)
        }
        #expect(actual == expected)
    }

    @Test("A drop report describes the event and the count")
    func reportDescription() {
        let sut = SamplingDropReport(eventName: "Scrolled", recordCount: 3, timestamps: Date(timeIntervalSince1970: 0) ... Date(timeIntervalSince1970: 1))
        let expected = "Scrolled: 3 sampled out"

        let actual = sut.description

        #expect(actual == expected)
    }

    @Test("Two trackers seeded by default decide differently")
    func defaultSeedRandom() async {
        func kept(_ tracker: Tracker) async -> [Int] {
            for number in 0 ..< 128 {
                tracker.track(Scrolled(number: number))
            }
            await tracker.finish()
            var numbers: [Int] = []
            for await record in tracker.records {
                numbers.append((record.event as? Scrolled)?.number ?? -1)
            }
            return numbers
        }
        let first = await kept(Tracker(samplers: [.events(of: Scrolled.self, rate: 0.5)]))

        let actual = await kept(Tracker(samplers: [.events(of: Scrolled.self, rate: 0.5)]))

        // Equal by chance with probability 2^-128.
        #expect(actual != first)
    }

    @Test("A no-op tracker's sampling drop reports are empty")
    func noOpReports() async {
        let sut = Tracker.noOp

        var reports = sut.samplingDropReports.makeAsyncIterator()

        #expect(await reports.next() == nil)
    }

    @Test("A rate in 0 ... 1 is made by the checked spelling, with its value")
    func checkedAccepts() throws {
        let expected = [0, 0.25, 1]

        let actual = try expected.map { try SampleRate(checked: $0).value }

        #expect(actual == expected)
    }

    @Test("The checked spelling throws InvalidSampleRate below 0, above 1 and for NaN", arguments: [-0.000_1, 1.000_1, Double.nan, -Double.infinity, Double.infinity])
    func checkedThrows(_ value: Double) {
        #expect(throws: InvalidSampleRate()) {
            try SampleRate(checked: value)
        }
    }

    @Test("Literals make rates: 0 and 1 as integers, fractions as floating point")
    func literals() {
        let zero: SampleRate = 0
        let one: SampleRate = 1
        let tenth: SampleRate = 0.1
        let expected = [0, 1, 0.1]

        let actual = [zero.value, one.value, tenth.value]

        #expect(actual == expected)
    }
}
