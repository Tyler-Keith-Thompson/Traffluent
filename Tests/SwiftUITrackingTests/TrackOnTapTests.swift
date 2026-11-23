#if os(macOS)
import AppKit
import Events
import SwiftUI
import SwiftUITracking
import Testing
import Trackers

@MainActor
@Suite("trackOnTap(_:)", .serialized, .timeLimit(.minutes(1)))
struct TrackOnTapTests {
    struct ShareTapped: Event, Equatable {}

    struct Shared: Event, Equatable {}

    @Test("Each tap tracks the event once, and the button still runs its action")
    func taps() async throws {
        let tracker = Tracker()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = Button("Share") { tracker.track(Shared()) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .trackOnTap(ShareTapped())
        let host = NSHostingView(rootView: view.tracker(tracker))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        let expected = ["ShareTapped", "Shared", "ShareTapped", "Shared"]

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp] {
            let click = NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            window.sendEvent(try #require(click))
        }
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append(type(of: record.event).name)
        }
        #expect(actual == expected)
    }

    @Test("A view that appears without a tap tracks nothing")
    func noTap() async {
        let tracker = Tracker()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = Text("Share")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .trackOnTap(ShareTapped())
        let host = NSHostingView(rootView: view.tracker(tracker))
        let expected = 0

        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual = 0
        for await _ in tracker.records {
            actual += 1
        }
        #expect(actual == expected)
    }

    @Test("The record's call site is where the modifier is applied")
    func callSite() async throws {
        let tracker = Tracker()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let expectedLine = #line + 1
        let view = Color.clear.contentShape(Rectangle()).trackOnTap(ShareTapped())
        let expectedFileID = #fileID
        let expectedFunction = #function
        let host = NSHostingView(rootView: view.tracker(tracker))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            window.sendEvent(try #require(click))
        }
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let actual = try #require(await records.next()?.sourceLocation)
        #expect(actual.line == expectedLine)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == expectedFunction)
    }
}
#endif
