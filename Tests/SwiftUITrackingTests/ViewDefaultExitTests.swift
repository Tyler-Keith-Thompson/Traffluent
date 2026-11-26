// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start, so this target's simulator run leaves them out. SwiftUI views
// are hosted in an AppKit window here, so they run on the Mac alone.
//
// Why child processes: `Tracker.bootstrap` sets the process's default tracker once, and nothing
// can reset it, so every test that bootstraps does it in a child process of its own. Each child
// checks what it sees and exits with a failure when it differs from what is expected.
#if os(macOS)
import AppKit
import Events
import Foundation
import SwiftUI
import SwiftUITracking
import Testing
import Trackers

@Suite("A view whose tracker was never set, with a tracker bootstrapped", .timeLimit(.minutes(1)))
struct ViewDefaultExitTests {
    struct CheckoutOpened: Event, Equatable {}

    struct Subscribed: Event, Equatable {}

    struct SubscribeButton: View {
        @Environment(\.tracker) private var tracker

        var body: some View {
            // As the examples do: the environment's tracker bound around the model's call, which
            // tracks through Tracker.current.
            Button("Subscribe") {
                withTracker(tracker) {
                    Tracker.current.track(Subscribed())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @Test("A screen with no tracker set tracks ScreenViewed and trackOnAppear's event through the bootstrapped tracker, carrying its ScreenKey")
    func screenReachesBootstrapped() async {
        await #expect(processExitsWith: .success) {
            let tracker = Tracker()
            let expected = ["CheckoutOpened Checkout", "ScreenViewed Checkout"]
            try Tracker.bootstrap(tracker)

            await MainActor.run {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                let host = NSHostingView(rootView: Text("Checkout").trackOnAppear(CheckoutOpened()).trackScreen("Checkout"))
                window.contentView = host
                host.layoutSubtreeIfNeeded()
            }
            await tracker.finish()

            var actual: [String] = []
            for await record in tracker.records {
                actual.append("\(type(of: record.event).name) \(record.context[ScreenKey.self] ?? "none")")
            }
            guard actual.sorted() == expected else { exit(EXIT_FAILURE) }
        }
    }

    @Test("A button's action binding a never-set environment tracker with withTracker tracks through the bootstrapped tracker, carrying the screen's ScreenKey")
    func boundEnvironmentReachesBootstrapped() async {
        await #expect(processExitsWith: .success) {
            let tracker = Tracker()
            let expected = ["Subscribed Plans"]
            try Tracker.bootstrap(tracker)

            let clicked = await MainActor.run {
                _ = NSApplication.shared
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                let host = NSHostingView(rootView: VStack { SubscribeButton() }.trackScreen("Plans"))
                window.contentView = host
                window.orderFrontRegardless()
                host.layoutSubtreeIfNeeded()
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let click = NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return false }
                    window.sendEvent(click)
                }
                return true
            }
            await tracker.finish()

            var actual: [String] = []
            for await record in tracker.records where !(record.event is ScreenViewed) {
                actual.append("\(type(of: record.event).name) \(record.context[ScreenKey.self] ?? "none")")
            }
            guard clicked, actual == expected else { exit(EXIT_FAILURE) }
        }
    }

    @Test("A screen given Tracker.noOp tracks nothing into the bootstrapped tracker")
    func explicitNoOpDrops() async {
        await #expect(processExitsWith: .success) {
            let tracker = Tracker()
            let expected: [String] = []
            try Tracker.bootstrap(tracker)

            await MainActor.run {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                let host = NSHostingView(rootView: Text("Checkout").trackOnAppear(CheckoutOpened()).trackScreen("Checkout").tracker(.noOp))
                window.contentView = host
                host.layoutSubtreeIfNeeded()
            }
            await tracker.finish()

            var actual: [String] = []
            for await record in tracker.records {
                actual.append(type(of: record.event).name)
            }
            guard actual == expected else { exit(EXIT_FAILURE) }
        }
    }
}
#endif
