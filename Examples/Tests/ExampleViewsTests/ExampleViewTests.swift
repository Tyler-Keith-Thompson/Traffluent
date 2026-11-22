// The tests run on the Mac; elsewhere this target builds empty, without ViewInspector.
#if os(macOS)
    import Destinations
    import Events
    import ExampleEvents
    import ExampleViews
    import Pipelines
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite("ExampleView", .serialized, .timeLimit(.minutes(1)))
    struct ExampleViewTests {
        // Taps track from a task of their own, so the test awaits the event's arrival here rather
        // than sleeping.
        final class Recorder: Destination {
            let (taps, continuation) = AsyncStream.makeStream(of: ButtonTapped.self)

            func receive(_ event: some Event) async {
                if let event = event as? ButtonTapped {
                    continuation.yield(event)
                }
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
            let sut = ExampleView(pipeline: Pipeline(recorder))
            let expected = ButtonTapped(label: "Share")

            try sut.inspect().find(button: "Share").tap()

            var taps = recorder.taps.makeAsyncIterator()
            let actual = await taps.next()
            #expect(actual == expected)
        }
    }
#endif
