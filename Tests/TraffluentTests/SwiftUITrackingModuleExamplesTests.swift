// The example of SwiftUITracking's landing article
// (Sources/SwiftUITracking/SwiftUITracking.docc/SwiftUITracking.md), verbatim, so the article cannot
// drift from the code. Its views are hosted in an AppKit window, so it runs on the Mac; elsewhere
// SwiftUITracking is empty and this file builds nothing.
#if os(macOS)
import AppKit
import SwiftUI
import Testing
import Traffluent

@MainActor
@Suite("SwiftUITracking module examples", .serialized, .timeLimit(.minutes(1)))
struct SwiftUITrackingModuleExamplesTests {
    @Event
    struct CartOpened {}

    @Event
    struct CheckoutStarted {
        var cartSize: Int
    }

    struct CartView: View {
        @Environment(\.tracker) private var tracker

        var body: some View {
            List {
                Button("Check out") {
                    tracker.track(CheckoutStarted(cartSize: 3))  // its record's context[ScreenKey.self] is "Cart"
                }
            }
            .trackOnAppear(CartOpened())
        }
    }

    @Test("Overview")
    func overview() async {
        let tracker = Tracker()
        let root = CartView()
            .trackScreen("Cart")  // tracks ScreenViewed(screen: "Cart") each time it appears
            .tracker(tracker)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: root)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await tracker.finish()
        var actual: [String: String?] = [:]
        for await record in tracker.records {
            actual[type(of: record.event).name] = record.context[ScreenKey.self]
        }
        let expected: [String: String?] = ["ScreenViewed": "Cart", "CartOpened": "Cart"]

        #expect(actual == expected)
    }
}
#endif
