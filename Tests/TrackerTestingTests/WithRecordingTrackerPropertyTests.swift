// Property tests against a naive reference: a recording holds exactly the events its body
// tracked, in order, and events(of:) is that list filtered to one type.

import Events
import PropertyBased
import Testing
import TrackerTesting
import Trackers
import TraffluentTestSupport

@Suite("withRecordingTracker: properties", .timeLimit(.minutes(1)))
struct WithRecordingTrackerPropertyTests {
    struct Viewed: Event, Equatable {
        var number: Int
    }

    struct Tapped: Event, Equatable {
        var number: Int
    }

    @Test("A recording's names and typed events match the events its body tracked, in order", .tags(.randomized))
    func matchesReference() async {
        await propertyCheck(count: 200, input: Gen.bool.array(of: 0 ... 40)) { kinds in
            let tracked = Array(kinds.enumerated())
            let expectedNames = tracked.map { $0.element ? "Viewed" : "Tapped" }
            let expectedViewed = tracked.filter(\.element).map { Viewed(number: $0.offset) }
            let expectedTapped = tracked.filter { !$0.element }.map { Tapped(number: $0.offset) }

            let actual = await withRecordingTracker {
                for (number, isViewed) in tracked {
                    if isViewed {
                        Tracker.current.track(Viewed(number: number))
                    } else {
                        Tracker.current.track(Tapped(number: number))
                    }
                }
            }

            #expect(actual.names == expectedNames)
            #expect(actual.events(of: Viewed.self) == expectedViewed)
            #expect(actual.events(of: Tapped.self) == expectedTapped)
        }
    }
}
