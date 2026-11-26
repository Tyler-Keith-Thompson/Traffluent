#if os(macOS)
import AppKit
import Events
import Instrumentation
import Observation
import SwiftUI
import SwiftUITracking
import Testing
import Trackers

@MainActor
@Suite("trackScreen(_:)", .serialized, .timeLimit(.minutes(1)))
struct TrackScreenTests {
    struct CheckoutStarted: Event, Equatable {}

    struct CouponShown: Event, Equatable {}

    struct CheckoutButton: View {
        @Environment(\.tracker) private var tracker

        var body: some View {
            Button("Check out") {
                tracker.track(CheckoutStarted())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @Observable
    final class Model {
        var isShown = true
        var title = "Checkout"
    }

    struct Screens: View {
        let model: Model

        var body: some View {
            VStack {
                Text(model.title)
                if model.isShown {
                    Text("Checkout")
                        .trackScreen("Checkout")
                }
            }
        }
    }

    @Test("A screen tracks ScreenViewed once when it appears, carrying its ScreenKey")
    func viewed() async throws {
        let tracker = Tracker()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: Screens(model: Model()).tracker(tracker))
        let expectedEvents = [ScreenViewed(screen: "Checkout")]
        let expectedScreens: [String?] = ["Checkout"]

        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actualEvents: [ScreenViewed] = []
        var actualScreens: [String?] = []
        for await record in tracker.records {
            actualEvents.append(try #require(record.event as? ScreenViewed))
            actualScreens.append(record.context[ScreenKey.self])
        }
        #expect(actualEvents == expectedEvents)
        #expect(actualScreens == expectedScreens)
    }

    @Test("A screen tracks ScreenViewed again each time it reappears, and not when it redraws")
    func reappear() async {
        let tracker = Tracker()
        let model = Model()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: Screens(model: model).tracker(tracker))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expected = [ScreenViewed(screen: "Checkout"), ScreenViewed(screen: "Checkout")]

        model.title = "Your checkout"
        host.layoutSubtreeIfNeeded()
        model.isShown = false
        host.layoutSubtreeIfNeeded()
        model.isShown = true
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual: [ScreenViewed] = []
        for await record in tracker.records {
            if let event = record.event as? ScreenViewed {
                actual.append(event)
            }
        }
        #expect(actual == expected)
    }

    @Test("An event a button's action inside the screen tracks through the environment's tracker carries the screen's ScreenKey")
    func buttonAction() async throws {
        let tracker = Tracker()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: VStack { CheckoutButton() }.trackScreen("Checkout").tracker(tracker))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        let expected: [String?] = ["Checkout"]

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            window.sendEvent(try #require(click))
        }
        await tracker.finish()

        var actual: [String?] = []
        for await record in tracker.records where record.event is CheckoutStarted {
            actual.append(record.context[ScreenKey.self])
        }
        #expect(actual == expected)
    }

    @Test("A tracking modifier applied inside the screen carries its ScreenKey; one applied outside doesn't")
    func insideAndOutside() async {
        let tracker = Tracker()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = Text("Coupon")
            .trackOnAppear(CouponShown())
            .trackScreen("Checkout")
            .trackOnAppear(CheckoutStarted())
        let host = NSHostingView(rootView: view.tracker(tracker))
        let expectedCoupon: [String?] = ["Checkout"]
        let expectedCheckout: [String?] = [nil]

        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actualCoupon: [String?] = []
        var actualCheckout: [String?] = []
        for await record in tracker.records {
            if record.event is CouponShown {
                actualCoupon.append(record.context[ScreenKey.self])
            } else if record.event is CheckoutStarted {
                actualCheckout.append(record.context[ScreenKey.self])
            }
        }
        #expect(actualCoupon == expectedCoupon)
        #expect(actualCheckout == expectedCheckout)
    }

    @Test("A screen inside another stamps its own name on the events inside it")
    func nested() async {
        let tracker = Tracker()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = Text("Coupon")
            .trackOnAppear(CouponShown())
            .trackScreen("Coupon")
            .trackScreen("Checkout")
        let host = NSHostingView(rootView: view.tracker(tracker))
        let expected = ["ScreenViewed Checkout", "ScreenViewed Coupon", "CouponShown Coupon"]

        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual: [String] = []
        for await record in tracker.records {
            actual.append("\(type(of: record.event).name) \(record.context[ScreenKey.self] ?? "none")")
        }
        #expect(actual.sorted() == expected.sorted())
    }

    @Observable
    final class Arrival {
        var tracker = Tracker.noOp
    }

    struct LateScreens: View {
        let model: Model
        let arrival: Arrival

        var body: some View {
            Screens(model: model).tracker(arrival.tracker)
        }
    }

    @Test("A screen that appears while its tracker is Tracker.noOp tracks ScreenViewed once another reaches it, carrying its ScreenKey")
    func trackerArrivesLater() async throws {
        let tracker = Tracker()
        let arrival = Arrival()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: LateScreens(model: Model(), arrival: arrival))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expectedEvents = [ScreenViewed(screen: "Checkout")]
        let expectedScreens: [String?] = ["Checkout"]

        arrival.tracker = tracker
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actualEvents: [ScreenViewed] = []
        var actualScreens: [String?] = []
        for await record in tracker.records {
            actualEvents.append(try #require(record.event as? ScreenViewed))
            actualScreens.append(record.context[ScreenKey.self])
        }
        #expect(actualEvents == expectedEvents)
        #expect(actualScreens == expectedScreens)
    }

    @Test("The ScreenViewed record's call site is where the modifier is applied")
    func callSite() async throws {
        let tracker = Tracker()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let expectedLine = #line + 1
        let view = Text("Checkout").trackScreen("Checkout")
        let expectedFileID = #fileID
        let expectedFunction = #function
        let host = NSHostingView(rootView: view.tracker(tracker))

        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let actual = try #require(await records.next()?.sourceLocation)
        #expect(actual.line == expectedLine)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == expectedFunction)
    }
}
#endif
