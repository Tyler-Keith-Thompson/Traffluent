import Testing
import TrackingPlans

// This target links Sessions, LifecycleTracking, SwiftUITracking and AutomaticControlTracking
// but imports none of them, so its binary references none of their events. Each library event's
// record sits in its event's own object file, and outside UIKit ControlActivated.swift is all that
// AutomaticControlTracking compiles. A link that pulled archive members in only for what something
// references would leave the events out, and TrackingPlan() would describe the app without them.
// Builds that can fail these tests: Bazel on Linux with alwayslink = False on one of the four
// modules, or on a Mac with that and -ObjC off (--features=-swift.objc_link_flag).
// That release builds' dead stripping keeps the records is covered upstream, by LinkerSets' own
// linking tests.
// The nine names must match the library events in DiscoveredEventTests.everyEvent, and their
// modules this target's row in scripts/modules.py.

@Suite("Discovery of library events nothing references")
struct UnreferencedEventDiscoveryTests {
    @Test(
        "TrackingPlan() describes each event of a linked library module whose type the program never names",
        arguments: [
            "SessionStarted",
            "SessionEnded",
            "ApplicationInstalled",
            "ApplicationUpdated",
            "ApplicationOpened",
            "ApplicationBackgrounded",
            "ApplicationTerminated",
            "ScreenViewed",
            "ControlActivated",
        ]
    )
    func unreferencedEvent(expected: String) throws {
        let actual = try TrackingPlan().schemas.map(\.name)

        #expect(actual.contains(expected))
    }
}
