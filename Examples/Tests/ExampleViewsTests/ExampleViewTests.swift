// The tests run on the Mac; elsewhere this target builds empty, without ViewInspector.
#if os(macOS)
    import Destinations
    import Events
    import ExampleEvents
    import ExampleViews
    import Pipelines
    import SwiftUI
    import Synchronization
    import Testing
    import ViewInspector

    @MainActor
    @Suite("ExampleView", .serialized, .timeLimit(.minutes(1)))
    struct ExampleViewTests {
        final class Recorder: Destination {
            let taps = Mutex<[ButtonTapped]>([])

            func receive(_ batch: [EventRecord]) async {
                taps.withLock { $0.append(contentsOf: batch.compactMap { $0.event as? ButtonTapped }) }
            }
        }

        @Test("The screen shows a button for each label, in order")
        func buttons() throws {
            let sut = ExampleView(pipeline: Pipeline())
            let expected = ["Subscribe", "Share"]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }

            #expect(actual == expected)
        }

        @Test("Tapping a button tracks ButtonTapped with its label")
        func tap() async throws {
            let recorder = Recorder()
            let pipeline = Pipeline(recorder)
            let sut = ExampleView(pipeline: pipeline)
            let expected = [ButtonTapped(label: "Share")]

            try sut.inspect().find(button: "Share").tap()
            pipeline.finish()
            try await pipeline.run().execute()

            let actual = recorder.taps.withLock { $0 }
            #expect(actual == expected)
        }
    }
#endif
