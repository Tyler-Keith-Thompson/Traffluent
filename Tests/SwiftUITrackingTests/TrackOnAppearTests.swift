#if os(macOS)
import AppKit
import Events
import Observation
import SwiftUI
import SwiftUITracking
import Testing
import Trackers

@MainActor
@Suite("trackOnAppear(_:)", .serialized, .timeLimit(.minutes(1)))
struct TrackOnAppearTests {
    struct CartOpened: Event, Equatable {
        var items: Int
    }

    @Observable
    final class Model {
        var isShown = true
        var title = "Cart"
    }

    struct Cart: View {
        let model: Model

        var body: some View {
            VStack {
                Text(model.title)
                if model.isShown {
                    Text("Items")
                        .trackOnAppear(CartOpened(items: 3))
                }
            }
        }
    }

    @Test("A view tracks its event once when it appears")
    func appear() async {
        let tracker = Tracker()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: Cart(model: Model()).tracker(tracker))
        let expected = [CartOpened(items: 3)]

        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual: [CartOpened] = []
        for await record in tracker.records {
            if let event = record.event as? CartOpened {
                actual.append(event)
            }
        }
        #expect(actual == expected)
    }

    @Test("Redrawing a view that stays on screen tracks nothing more")
    func redraw() async {
        let tracker = Tracker()
        let model = Model()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: Cart(model: model).tracker(tracker))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expected = [CartOpened(items: 3)]

        model.title = "Your cart"
        host.layoutSubtreeIfNeeded()
        host.rootView = Cart(model: model).tracker(tracker)
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual: [CartOpened] = []
        for await record in tracker.records {
            if let event = record.event as? CartOpened {
                actual.append(event)
            }
        }
        #expect(actual == expected)
    }

    @Test("A view that disappears and appears again tracks its event again")
    func reappear() async {
        let tracker = Tracker()
        let model = Model()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: Cart(model: model).tracker(tracker))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expected = [CartOpened(items: 3), CartOpened(items: 3)]

        model.isShown = false
        host.layoutSubtreeIfNeeded()
        model.isShown = true
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual: [CartOpened] = []
        for await record in tracker.records {
            if let event = record.event as? CartOpened {
                actual.append(event)
            }
        }
        #expect(actual == expected)
    }

    @Observable
    final class Arrival {
        var tracker = Tracker.noOp
    }

    struct LateCart: View {
        let model: Model
        let arrival: Arrival

        var body: some View {
            Cart(model: model).tracker(arrival.tracker)
        }
    }

    @Test("A view that appears before a tracker reaches it tracks its event once one does")
    func trackerArrivesLater() async {
        let tracker = Tracker()
        let arrival = Arrival()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: LateCart(model: Model(), arrival: arrival))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expected = [CartOpened(items: 3)]

        arrival.tracker = tracker
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual: [CartOpened] = []
        for await record in tracker.records {
            if let event = record.event as? CartOpened {
                actual.append(event)
            }
        }
        #expect(actual == expected)
    }

    @Test("A view that disappears before a tracker reaches it tracks nothing once one does")
    func trackerArrivesAfterDisappearing() async {
        let tracker = Tracker()
        let model = Model()
        let arrival = Arrival()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: LateCart(model: model, arrival: arrival))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        model.isShown = false
        host.layoutSubtreeIfNeeded()
        let expected: [CartOpened] = []

        arrival.tracker = tracker
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual: [CartOpened] = []
        for await record in tracker.records {
            if let event = record.event as? CartOpened {
                actual.append(event)
            }
        }
        #expect(actual == expected)
    }

    @Test("A view that appeared with a tracker tracks nothing more when its tracker goes and another arrives")
    func trackerReplaced() async {
        let firstTracker = Tracker()
        let secondTracker = Tracker()
        let arrival = Arrival()
        arrival.tracker = firstTracker
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: LateCart(model: Model(), arrival: arrival))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expectedFirst = [CartOpened(items: 3)]
        let expectedSecond: [CartOpened] = []

        arrival.tracker = .noOp
        host.layoutSubtreeIfNeeded()
        arrival.tracker = secondTracker
        host.layoutSubtreeIfNeeded()
        await firstTracker.finish()
        await secondTracker.finish()

        var actualFirst: [CartOpened] = []
        for await record in firstTracker.records {
            if let event = record.event as? CartOpened {
                actualFirst.append(event)
            }
        }
        var actualSecond: [CartOpened] = []
        for await record in secondTracker.records {
            if let event = record.event as? CartOpened {
                actualSecond.append(event)
            }
        }
        #expect(actualFirst == expectedFirst)
        #expect(actualSecond == expectedSecond)
    }

    @Test("The record's call site is where the modifier is applied")
    func callSite() async throws {
        let tracker = Tracker()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let expectedLine = #line + 1
        let view = Text("Items").trackOnAppear(CartOpened(items: 3))
        // #column, as a default argument, is the column of the call's opening parenthesis.
        let expectedColumn = 47
        let expectedFile = #file
        let expectedFileID = #fileID
        let expectedFunction = #function
        let host = NSHostingView(rootView: view.tracker(tracker))

        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let actual = try #require(await records.next()?.sourceLocation)
        #expect(actual.line == expectedLine)
        #expect(actual.column == expectedColumn)
        #expect(actual.file == expectedFile)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == expectedFunction)
    }
}
#endif
