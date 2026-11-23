// Property tests against a naive reference: a consent gating a tracker delivers, holds and drops
// events, and reports the drops, as a model built from plain arrays does, for any sequence of
// tracks and decisions and any hold bound.

import Destinations
import Events
import Foundation
import PropertyBased
import TraffluentTestSupport
import Testing
import Trackers

@Suite("Consent: properties", .timeLimit(.minutes(1)))
struct ConsentPropertyTests {
    struct Viewed: Event {
        var number: Int
    }

    struct AdClicked: Event {
        static let consentCategory = ConsentCategory.advertising
        var number: Int
    }

    struct ChatOpened: Event {
        static let consentCategory = ConsentCategory.functional
        var number: Int
    }

    /// What the gate should do, kept in plain arrays: each event is its number, tracked at that
    /// many seconds after 1970.
    struct Model {
        static let categories: [ConsentCategory] = [.analytics, .advertising, .functional]

        let limit: Int
        var statuses: [ConsentCategory: ConsentStatus] = [:]
        var held: [(number: Int, category: ConsentCategory)] = []
        var delivered: [Int] = []
        var reports: [ConsentDropReport] = []

        mutating func track(_ number: Int, _ category: ConsentCategory) {
            switch statuses[category, default: .undecided] {
            case .granted:
                delivered.append(number)
            case .denied:
                break
            case .undecided:
                held.append((number, category))
                if held.count > limit {
                    let dropped = Date(timeIntervalSince1970: Double(held.removeFirst().number))
                    // Read only at the end, so an overflow merges into one right before it.
                    if case .heldRecordLimit(let count, let timestamps) = reports.last {
                        reports[reports.count - 1] = .heldRecordLimit(
                            recordCount: count + 1, timestamps: min(timestamps.lowerBound, dropped) ... max(timestamps.upperBound, dropped))
                    } else {
                        reports.append(.heldRecordLimit(recordCount: 1, timestamps: dropped ... dropped))
                    }
                }
            }
        }

        mutating func decide(_ category: ConsentCategory, _ status: ConsentStatus) {
            statuses[category] = status
            let decided = held.filter { $0.category == category }.map(\.number)
            held.removeAll { $0.category == category }
            if status == .granted {
                delivered += decided
            } else if let range = Self.range(decided) {
                reports.append(.denied(category: category, recordCount: decided.count, timestamps: range))
            }
        }

        mutating func finish() {
            if let range = Self.range(held.map(\.number)) {
                reports.append(.finishedUndecided(recordCount: held.count, timestamps: range))
            }
            held = []
        }

        static func range(_ numbers: [Int]) -> ClosedRange<Date>? {
            guard let low = numbers.min(), let high = numbers.max() else { return nil }
            return Date(timeIntervalSince1970: Double(low)) ... Date(timeIntervalSince1970: Double(high))
        }
    }

    @Test("Any sequence of tracks, grants and denials delivers and reports what a naive model does", .tags(.randomized))
    func matchesModel() async {
        // Each operation is a number from 0 to 8: 0-2 track an event of category 0-2, 3-5 grant
        // it, 6-8 deny it.
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 8).array(of: 0 ... 40), Gen.int(in: 0 ... 4)) { operations, limit in
            var model = Model(limit: limit)
            var expectedHeld: [Int] = []
            for (number, operation) in operations.enumerated() {
                let category = Model.categories[operation % 3]
                switch operation / 3 {
                case 0: model.track(number, category)
                case 1: model.decide(category, .granted)
                default: model.decide(category, .denied)
                }
                expectedHeld.append(model.held.count)
            }
            model.finish()

            let (delivered, actualHeld, reports) = try await run(operations, limit: limit)
            var actualReports: [ConsentDropReport] = []
            for await report in reports {
                actualReports.append(report)
            }

            #expect(delivered == model.delivered)
            #expect(actualHeld == expectedHeld)
            #expect(actualReports == model.reports)
        }
    }

    /// Runs `operations` through a tracker gated by a consent holding `limit` records, delivers
    /// what it lets through, and returns the numbers delivered, how many records were held after
    /// each operation, and the consent's drop reports, which end as the consent goes away when
    /// this returns.
    func run(_ operations: [Int], limit: Int) async throws -> ([Int], [Int], AsyncStream<ConsentDropReport>) {
        let consent = Consent(heldRecordLimit: limit)
        let tracker = Tracker(consent: consent, now: { Date(timeIntervalSince1970: Double(Clock.number)) })
        let recorder = InMemoryDestination()
        var held: [Int] = []
        for (number, operation) in operations.enumerated() {
            let category = Model.categories[operation % 3]
            switch operation / 3 {
            case 0:
                Clock.$number.withValue(number) {
                    switch operation {
                    case 0: tracker.track(Viewed(number: number))
                    case 1: tracker.track(AdClicked(number: number))
                    default: tracker.track(ChatOpened(number: number))
                    }
                }
            case 1: consent.grant(category)
            default: consent.deny(category)
            }
            await tracker.flush()
            held.append(consent.heldRecordCount)
        }
        await tracker.finish()
        try await tracker.records.batch(strategy: .count(50)).deliver(to: recorder).execute()
        let delivered = recorder.records.compactMap { record -> Int? in
            switch record.event {
            case let event as Viewed: event.number
            case let event as AdClicked: event.number
            case let event as ChatOpened: event.number
            default: nil
            }
        }
        return (delivered, held, consent.dropReports)
    }

    /// The number of the event being tracked, which the tracker's clock stamps it with.
    enum Clock {
        @TaskLocal static var number = 0
    }
}
