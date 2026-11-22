// The tests run on the Mac; elsewhere this target builds empty, without ViewInspector.
#if os(macOS)
    import DestinationTesting
    import Destinations
    import Events
    import ExampleEvents
    import ExampleViews
    import Pipelines
    import SwiftUI
    import Testing
    import Trackers
    import ViewInspector

    @MainActor
    @Suite("ExampleView", .serialized, .timeLimit(.minutes(1)))
    struct ExampleViewTests {
        @Test("The screen shows a button for each label, in order")
        func buttons() throws {
            let sut = ExampleView(tracker: .noOp)
            let expected = ["Subscribe", "Share"]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }

            #expect(actual == expected)
        }

        @Test("Tapping a button tracks ButtonTapped with its label")
        func tap() async throws {
            let recorder = InMemoryDestination()
            let pipeline = Pipeline(recorder)
            let sut = ExampleView(tracker: Tracker(pipeline))
            let expected = [ButtonTapped(label: "Share")]

            try sut.inspect().find(button: "Share").tap()
            pipeline.finish()
            try await pipeline.run().execute()

            let actual = recorder.events(of: ButtonTapped.self)
            #expect(actual == expected)
        }
    }
#endif
