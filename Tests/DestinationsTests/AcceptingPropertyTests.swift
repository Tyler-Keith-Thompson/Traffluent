// Property tests against a naive reference: a destination accepting some categories receives the
// tracked events filtered to those categories, batch by batch, with empty batches left out.

import Destinations
import Events
import PropertyBased
import TraffluentTestSupport
import Testing
import Trackers

@Suite("accepting(_:): properties", .timeLimit(.minutes(1)))
struct AcceptingPropertyTests {
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

    struct Recommended: Event {
        static let consentCategory = ConsentCategory.personalization
        var number: Int
    }

    @Test("Under a count strategy, an accepting destination receives each batch filtered to its categories, empty ones left out", .tags(.randomized))
    func filteredBatches() async {
        let categories: [ConsentCategory] = [.analytics, .advertising, .functional, .personalization]
        await propertyCheck(count: 200, input: Gen.int(in: 0 ... 3).array(of: 0 ... 30), Gen.int(in: 0 ... 3).set(ofAtMost: 0 ... 4), Gen.int(in: 1 ... 5)) { kinds, acceptedKinds, size in
            let recorder = InMemoryDestination()
            let tracker = Tracker()
            let accepted = acceptedKinds.sorted().map { categories[$0] }
            let sut = tracker.records.batch(strategy: .count(size)).deliver(to: recorder.accepting(accepted))
            let tracked = Array(kinds.enumerated())
            let expected = stride(from: 0, to: tracked.count, by: size)
                .map { tracked[$0 ..< min($0 + size, tracked.count)].filter { acceptedKinds.contains($0.element) }.map(\.offset) }
                .filter { !$0.isEmpty }

            for (number, kind) in tracked {
                switch kind {
                case 0: tracker.track(Viewed(number: number))
                case 1: tracker.track(AdClicked(number: number))
                case 2: tracker.track(ChatOpened(number: number))
                default: tracker.track(Recommended(number: number))
                }
            }
            await tracker.finish()
            try await sut.execute()

            #expect(recorder.numbers == expected)
        }
    }
}

extension Destination {
    /// This destination accepting `categories`, given as an array.
    fileprivate func accepting(_ categories: [ConsentCategory]) -> any Destination {
        switch categories.count {
        case 0: accepting()
        case 1: accepting(categories[0])
        case 2: accepting(categories[0], categories[1])
        case 3: accepting(categories[0], categories[1], categories[2])
        default: accepting(categories[0], categories[1], categories[2], categories[3])
        }
    }
}

extension InMemoryDestination {
    /// The numbers of the events received, batch by batch.
    fileprivate var numbers: [[Int]] {
        batches.map { batch in
            batch.compactMap { record in
                switch record.event {
                case let event as AcceptingPropertyTests.Viewed: event.number
                case let event as AcceptingPropertyTests.AdClicked: event.number
                case let event as AcceptingPropertyTests.ChatOpened: event.number
                case let event as AcceptingPropertyTests.Recommended: event.number
                default: nil
                }
            }
        }
    }
}
