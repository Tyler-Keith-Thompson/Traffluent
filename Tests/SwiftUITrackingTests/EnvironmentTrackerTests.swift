// SwiftUI views are hosted in an AppKit window, so the tests run on the Mac; elsewhere this
// target builds empty.
#if os(macOS)
import AppKit
import Events
import SwiftUI
import SwiftUITracking
import Testing
import Trackers

@MainActor
@Suite("EnvironmentValues.tracker", .serialized, .timeLimit(.minutes(1)))
struct EnvironmentTrackerTests {
    struct Subscribed: Event, Equatable {
        var plan: String
    }

    struct SubscribeButton: View {
        @Environment(\.tracker) private var tracker

        var body: some View {
            Button("Subscribe") {
                tracker.track(Subscribed(plan: "pro"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @Test("Without a tracker set, the environment's tracker drops every event")
    func defaultDrops() async {
        let sut = EnvironmentValues().tracker
        let expected = 0

        sut.track(Subscribed(plan: "pro"))
        await sut.finish()

        var actual = 0
        for await _ in sut.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("A button's action tracks through the tracker set at the root, read from the environment")
    func buttonReadsEnvironment() async throws {
        let tracker = Tracker()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: VStack { SubscribeButton() }.tracker(tracker))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        let expected = [Subscribed(plan: "pro")]

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            window.sendEvent(try #require(click))
        }
        await tracker.finish()

        var actual: [Subscribed] = []
        for await record in tracker.records {
            if let event = record.event as? Subscribed {
                actual.append(event)
            }
        }
        #expect(actual == expected)
    }

    @Test("A tracker set inside another replaces it for the views inside")
    func nestedReplaces() async throws {
        let outer = Tracker()
        let inner = Tracker()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: VStack { SubscribeButton().tracker(inner) }.tracker(outer))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        let expectedInner = 1
        let expectedOuter = 0

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            window.sendEvent(try #require(click))
        }
        await outer.finish()
        await inner.finish()

        var actualInner = 0
        for await _ in inner.records {
            actualInner += 1
        }
        var actualOuter = 0
        for await _ in outer.records {
            actualOuter += 1
        }
        #expect(actualInner == expectedInner)
        #expect(actualOuter == expectedOuter)
    }
}
#endif
