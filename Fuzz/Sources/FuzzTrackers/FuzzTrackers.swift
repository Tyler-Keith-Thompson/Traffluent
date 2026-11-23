// Consent's gate against a model of plain arrays: two trackers share one consent, and a sequence
// of choices tracks events of three categories on either, grants or denies a category, or
// finishes a tracker. After every operation both trackers' workers are flushed; then the consent
// holds as many records as the model, and the reports since the last operation are the model's
// (in any order across the two trackers, whose workers run at once). At the end each tracker's
// records are the model's, in order, and once the consent is gone no report is left over. Each
// event is its number, tracked that many seconds after 1970, and the hold's bound is small, so
// overflows and ties are common.

import Foundation
import FuzzSupport
import Synchronization
import Trackers
import Events

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

let categories: [ConsentCategory] = [.analytics, .advertising, .functional]

/// What the gate should do.
struct Model {
    let limit: Int
    var statuses: [ConsentCategory: ConsentStatus] = [:]
    /// Held records: number, category and tracker.
    var held: [(number: Int, category: ConsentCategory, tracker: Int)] = []
    var delivered: [[Int]] = [[], []]
    var finished: [Bool] = [false, false]

    /// Tracks `number` on `tracker`, returning the reports it makes.
    mutating func track(_ number: Int, _ category: ConsentCategory, on tracker: Int) -> [ConsentDropReport] {
        // A finished tracker drops what it is given.
        guard !finished[tracker] else { return [] }
        switch statuses[category, default: .undecided] {
        case .granted:
            delivered[tracker].append(number)
        case .denied:
            break
        case .undecided:
            held.append((number, category, tracker))
            if held.count > limit {
                let dropped = Date(timeIntervalSince1970: Double(held.removeFirst().number))
                return [.heldRecordLimit(recordCount: 1, timestamps: dropped ... dropped)]
            }
        }
        return []
    }

    /// Decides `category`, returning the reports it makes: one per tracker that held any of it.
    mutating func decide(_ category: ConsentCategory, _ status: ConsentStatus) -> [ConsentDropReport] {
        statuses[category] = status
        var reports: [ConsentDropReport] = []
        for tracker in finished.indices where !finished[tracker] {
            let decided = held.filter { $0.category == category && $0.tracker == tracker }.map(\.number)
            held.removeAll { $0.category == category && $0.tracker == tracker }
            if status == .granted {
                delivered[tracker] += decided
            } else if let range = Self.range(decided) {
                reports.append(.denied(category: category, recordCount: decided.count, timestamps: range))
            }
        }
        return reports
    }

    /// Finishes `tracker`, returning the reports it makes.
    mutating func finish(_ tracker: Int) -> [ConsentDropReport] {
        let dropped = held.filter { $0.tracker == tracker }.map(\.number)
        held.removeAll { $0.tracker == tracker }
        finished[tracker] = true
        guard let range = Self.range(dropped) else { return [] }
        return [.finishedUndecided(recordCount: dropped.count, timestamps: range)]
    }

    static func range(_ numbers: [Int]) -> ClosedRange<Date>? {
        guard let low = numbers.min(), let high = numbers.max() else { return nil }
        return Date(timeIntervalSince1970: Double(low)) ... Date(timeIntervalSince1970: Double(high))
    }
}

/// A value shared with a closure: a `Mutex` itself can't be captured, as it can't be copied.
final class Shared<Value: Sendable>: Sendable {
    let value: Mutex<Value>

    init(_ value: Value) {
        self.value = Mutex(value)
    }
}

/// Runs `body` to completion from synchronous code: the fuzzer's callback can't await.
func blocking<Value: Sendable>(_ body: @escaping @Sendable () async -> Value) -> Value {
    let result = Shared<Value?>(nil)
    let done = DispatchSemaphore(value: 0)
    Task {
        let value = await body()
        result.value.withLock { $0 = value }
        done.signal()
    }
    done.wait()
    // The task set it before signalling.
    return result.value.withLock { $0! }
}

/// The numbers of `tracker`'s records, read until they end.
func numbers(of tracker: Tracker) -> [Int] {
    blocking {
        var numbers: [Int] = []
        for await record in tracker.records {
            switch record.event {
            case let event as Viewed: numbers.append(event.number)
            case let event as AdClicked: numbers.append(event.number)
            case let event as ChatOpened: numbers.append(event.number)
            default: break
            }
        }
        return numbers
    }
}

/// The next `count` reports, waiting for each.
func next(_ count: Int, of reports: AsyncStream<ConsentDropReport>) -> [ConsentDropReport] {
    blocking {
        var iterator = reports.makeAsyncIterator()
        var next: [ConsentDropReport] = []
        while next.count < count, let report = await iterator.next() {
            next.append(report)
        }
        return next
    }
}

/// Whether `actual` holds the reports `expected` does, as many times each, in any order.
func sameReports(_ actual: [ConsentDropReport], _ expected: [ConsentDropReport]) -> Bool {
    var remaining = actual
    for report in expected {
        guard let index = remaining.firstIndex(of: report) else { return false }
        remaining.remove(at: index)
    }
    return remaining.isEmpty
}

/// Runs `input`'s operations and checks them against the model; returns the consent's reports.
func run(_ input: inout FuzzInput, model: inout Model) -> AsyncStream<ConsentDropReport> {
    let consent = Consent(heldRecordLimit: model.limit)
    let reports = consent.dropReports
    let clock = Shared(0)
    let trackers = (0 ..< 2).map { _ in Tracker(consent: consent, now: { Date(timeIntervalSince1970: Double(clock.value.withLock { $0 })) }) }
    var number = 0
    while !input.isEmpty {
        let operation = input.int(below: 4)
        let category = categories[input.int(below: categories.count)]
        let tracker = input.int(below: trackers.count)
        let expected: [ConsentDropReport]
        switch operation {
        case 0, 1:
            number += 1
            clock.value.withLock { $0 = number }
            switch categories.firstIndex(of: category) {
            case 0: trackers[tracker].track(Viewed(number: number))
            case 1: trackers[tracker].track(AdClicked(number: number))
            default: trackers[tracker].track(ChatOpened(number: number))
            }
            expected = model.track(number, category, on: tracker)
        case 2:
            let status: ConsentStatus = input.int(below: 2) == 0 ? .granted : .denied
            if status == .granted {
                consent.grant(category)
            } else {
                consent.deny(category)
            }
            expected = model.decide(category, status)
        default:
            // A finished tracker finishing again changes nothing in the model or the gate.
            guard !model.finished[tracker] else { continue }
            let finishing = trackers[tracker]
            blocking { await finishing.finish() }
            expected = model.finish(tracker)
        }
        let flushing = trackers
        blocking {
            for tracker in flushing {
                await tracker.flush()
            }
        }
        let actual = next(expected.count, of: reports)
        check(sameReports(actual, expected), "reported \(actual), model \(expected)")
        check(consent.heldRecordCount == model.held.count, "held \(consent.heldRecordCount), model holds \(model.held.count)")
    }
    for tracker in trackers.indices where !model.finished[tracker] {
        let finishing = trackers[tracker]
        blocking { await finishing.finish() }
        let expected = model.finish(tracker)
        let actual = next(expected.count, of: reports)
        check(sameReports(actual, expected), "reported \(actual) at the end, model \(expected)")
    }
    for tracker in trackers.indices {
        let actual = numbers(of: trackers[tracker])
        check(actual == model.delivered[tracker], "tracker \(tracker) delivered \(actual), model \(model.delivered[tracker])")
    }
    return reports
}

@main
enum FuzzTrackers {
    static func main() {
        runFuzzer { input in
            var model = Model(limit: input.int(in: 0 ... 4))
            // The consent goes away as run returns, which ends its reports after the last.
            let reports = run(&input, model: &model)
            let actual = next(Int.max, of: reports)
            check(actual.isEmpty, "reported \(actual) beyond the model's")
        }
    }
}
