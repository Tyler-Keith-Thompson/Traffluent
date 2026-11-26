// The SwiftUI example of the "Tracking from SwiftUI, UIKit and AppKit" article
// (Sources/Traffluent/Traffluent.docc/TrackingFromViews.md), verbatim. Its views are hosted in an
// AppKit window, so it runs on the Mac; elsewhere SwiftUITracking is empty and this file builds
// nothing.
#if os(macOS)
import AppKit
import SwiftUI
import Testing
import Traffluent

@MainActor
@Suite("Tracking from views examples: SwiftUI", .serialized, .timeLimit(.minutes(1)))
struct TrackingFromViewsSwiftUIExampleTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    @Event
    struct PlanSelected {
        var plan: String
    }

    struct CheckoutView: View {
        @Environment(\.tracker) private var tracker
        @State private var plan = "free"

        var body: some View {
            Form {
                Picker("Plan", selection: $plan) {
                    Text("Free").tag("free")
                    Text("Pro").tag("pro")
                }
                .trackChange(of: plan) { PlanSelected(plan: $0) }
                Button("Sign up") {
                    tracker.track(SignedUp(plan: plan))  // its record's context[ScreenKey.self] is "Checkout"
                }
            }
        }
    }

    @Test("SwiftUI")
    func swiftUI() async throws {
        let tracker = Tracker()
        let root = CheckoutView()
            .trackScreen("Checkout")  // tracks ScreenViewed(screen: "Checkout") each time it appears
            .tracker(tracker)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: root)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await tracker.finish()
        var records = tracker.records.makeAsyncIterator()
        let record = try #require(await records.next())

        #expect(record.event as? ScreenViewed == ScreenViewed(screen: "Checkout"))
        #expect(record.context[ScreenKey.self] == "Checkout")
    }
}
#endif
