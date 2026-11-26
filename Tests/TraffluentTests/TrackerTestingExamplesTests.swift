// The examples in TrackerTesting's documentation, verbatim, so the docs cannot drift from the code.

import Testing
import TrackerTesting
import Traffluent

@Suite("TrackerTesting examples", .timeLimit(.minutes(1)))
struct TrackerTestingExamplesTests {
    @Event
    struct SignedUp: Equatable {
        var plan: String
    }

    @Test("withRecordingTracker, sync body")
    func syncBody() async {
        let tracked = await withRecordingTracker {
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
    }

    @Test("withRecordingTracker, async body")
    func asyncBody() async {
        let tracked = await withRecordingTracker {
            await Task.yield()
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        #expect(tracked.names == ["SignedUp"])
    }

    @Test("withRecordingTracker, async body given the tracker")
    func asyncBodyGivenTheTracker() async {
        let tracked = await withRecordingTracker { tracker in
            await Task.yield()
            tracker.track(SignedUp(plan: "pro"))
        }
        #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
    }
}

// The SwiftUI example: its view is hosted in an NSHostingView, so it runs on the Mac; elsewhere
// SwiftUITracking is empty.
#if os(macOS)
import AppKit
import SwiftUI

@MainActor
@Suite("TrackerTesting examples: SwiftUI", .serialized, .timeLimit(.minutes(1)))
struct TrackerTestingSwiftUIExampleTests {
    @Event
    struct CheckoutViewed: Equatable {}

    struct CheckoutView: View {
        var body: some View {
            Text("Checkout")
                .trackOnAppear(CheckoutViewed())
        }
    }

    @Test("withRecordingTracker, a SwiftUI view given the tracker")
    func swiftUI() async {
        let tracked = await withRecordingTracker { tracker in
            let host = NSHostingView(rootView: CheckoutView().tracker(tracker))
            host.layoutSubtreeIfNeeded()
        }
        #expect(tracked.events(of: CheckoutViewed.self) == [CheckoutViewed()])
    }
}
#endif
