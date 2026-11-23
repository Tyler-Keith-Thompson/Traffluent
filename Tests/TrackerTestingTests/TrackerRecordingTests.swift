import Events
import Testing
import TrackerTesting
import Trackers

@Suite("TrackerRecording", .timeLimit(.minutes(1)))
struct TrackerRecordingTests {
    struct SignedUp: Event, Equatable {
        var plan: String
    }

    struct Viewed: Event, Equatable {
        static let name = "screen_viewed"
        var number: Int
    }

    @Test("events(of:) returns only the events of that type, in the order tracked")
    func eventsOfType() async {
        let expectedSignedUp = [SignedUp(plan: "free"), SignedUp(plan: "pro")]
        let expectedViewed = [Viewed(number: 1)]

        let actual = await withRecordingTracker {
            Tracker.current.track(SignedUp(plan: "free"))
            Tracker.current.track(Viewed(number: 1))
            Tracker.current.track(SignedUp(plan: "pro"))
        }

        #expect(actual.events(of: SignedUp.self) == expectedSignedUp)
        #expect(actual.events(of: Viewed.self) == expectedViewed)
    }

    @Test("events(of:) is empty for a type that wasn't tracked")
    func eventsOfUntrackedType() async {
        let actual = await withRecordingTracker {
            Tracker.current.track(SignedUp(plan: "pro"))
        }

        #expect(actual.events(of: Viewed.self).isEmpty)
    }

    @Test("names lists every event's name, whatever its type, in the order tracked")
    func names() async {
        let expected = ["SignedUp", "screen_viewed", "SignedUp"]

        let actual = await withRecordingTracker {
            Tracker.current.track(SignedUp(plan: "free"))
            Tracker.current.track(Viewed(number: 1))
            Tracker.current.track(SignedUp(plan: "pro"))
        }

        #expect(actual.names == expected)
    }

    @Test("records hold each event with its call site")
    func records() async throws {
        let expectedLine = #line + 3

        let actual = await withRecordingTracker {
            Tracker.current.track(SignedUp(plan: "pro"))
        }

        let record = try #require(actual.records.first)
        #expect(actual.records.count == 1)
        #expect(record.event as? SignedUp == SignedUp(plan: "pro"))
        #expect(record.sourceLocation?.line == expectedLine)
    }
}
