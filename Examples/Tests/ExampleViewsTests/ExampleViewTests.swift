// The tests run on the Mac; elsewhere this target builds empty, without ViewInspector.
#if os(macOS)
    import AppKit
    import Destinations
    import Events
    import ExampleEvents
    import ExampleViews
    import Instrumentation
    import SwiftUI
    import SwiftUITracking
    import Testing
    import Trackers
    import ViewInspector

    @MainActor
    @Suite("ExampleView", .serialized, .timeLimit(.minutes(1)))
    struct ExampleViewTests {
        @Test("The screen shows a button for each label, in order")
        func buttons() throws {
            let sut = ExampleView()
            let expected = ["Subscribe", "Share"]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }

            #expect(actual == expected)
        }

        @Test("Tapping a button tracks ButtonTapped with its label through the environment's tracker")
        func tap() async throws {
            let recorder = InMemoryDestination()
            let tracker = Tracker()
            let sut = ExampleView().tracker(tracker)
            let expected = [ButtonTapped(label: "Share")]

            try sut.inspect().find(button: "Share").tap()
            await tracker.finish()
            try await tracker.records.batch().deliver(to: recorder).execute()

            let actual = recorder.events(of: ButtonTapped.self)
            #expect(actual == expected)
        }

        @Test("Placed as a screen, it tracks ScreenViewed as it appears, and a tap's record carries the screen's ScreenKey")
        func screen() async throws {
            let tracker = Tracker()
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let host = NSHostingView(rootView: ExampleView().frame(width: 200, height: 200).trackScreen("Home").tracker(tracker))
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            let expected = ["ScreenViewed Home", "ButtonTapped Home"]

            // The window's centre is on the first button, "Subscribe".
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let click = NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                window.sendEvent(try #require(click))
            }
            await tracker.finish()

            var actual: [String] = []
            for await record in tracker.records {
                actual.append("\(type(of: record.event).name) \(record.context[ScreenKey.self] ?? "none")")
            }
            #expect(actual == expected)
        }
    }
#endif
