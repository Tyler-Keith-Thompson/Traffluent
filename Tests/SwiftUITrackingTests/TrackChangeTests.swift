#if os(macOS)
import AppKit
import Events
import Observation
import SwiftUI
import SwiftUITracking
import Testing
import Trackers

@MainActor
@Suite("trackChange(of:_:)", .serialized, .timeLimit(.minutes(1)))
struct TrackChangeTests {
    struct PlanSelected: Event, Equatable {
        var plan: String
    }

    @Observable
    final class Model {
        var plan = "free"
    }

    struct PlanPicker: View {
        let model: Model

        var body: some View {
            Text(model.plan)
                .trackChange(of: model.plan) { PlanSelected(plan: $0) }
        }
    }

    @Test("Each change tracks one event made from the new value; the first value and an equal one track none")
    func changes() async {
        let tracker = Tracker()
        let model = Model()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: PlanPicker(model: model).tracker(tracker))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expected = [PlanSelected(plan: "pro"), PlanSelected(plan: "team")]

        model.plan = "pro"
        host.layoutSubtreeIfNeeded()
        model.plan = "pro"
        host.layoutSubtreeIfNeeded()
        model.plan = "team"
        host.layoutSubtreeIfNeeded()
        await tracker.finish()

        var actual: [PlanSelected] = []
        for await record in tracker.records {
            if let event = record.event as? PlanSelected {
                actual.append(event)
            }
        }
        #expect(actual == expected)
    }

    struct LocatedPlanPicker: View {
        static let line = #line + 4
        let model: Model

        var body: some View {
            Text(model.plan).trackChange(of: model.plan) { PlanSelected(plan: $0) }
        }
    }

    @Test("The record's call site is where the modifier is applied")
    func callSite() async throws {
        let tracker = Tracker()
        let model = Model()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: LocatedPlanPicker(model: model).tracker(tracker))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let expectedLine = LocatedPlanPicker.line
        let expectedFileID = #fileID
        let expectedFunction = "body"

        model.plan = "pro"
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
