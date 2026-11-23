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
