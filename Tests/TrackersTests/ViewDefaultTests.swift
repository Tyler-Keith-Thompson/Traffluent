import Events
import Instrumentation
import Testing
import Trackers

// No test here bootstraps a tracker, which would change every other test in the process; the
// bootstrapped behaviour is in ViewDefaultExitTests.
@Suite("Tracker.viewDefault: a view's tracker that was never set", .timeLimit(.minutes(1)))
struct ViewDefaultTests {
    struct Tapped: Event {
        var number: Int
    }

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Outside a preview, a never-set view tracker isn't a no-op tracker, nor is its enriched copy")
    func notNoOp() {
        let environment: [String: String] = [:]
        let sut = Tracker.viewDefault(environment: environment)

        let actual = sut.isNoOp
        let actualEnriched = sut.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" }).isNoOp

        #expect(!actual)
        #expect(!actualEnriched)
    }

    @Test("withTracker given a never-set view tracker, or its enriched copy, inside another binding stands for the bound tracker, running the bound copy's enrichers, then the view copy's")
    func bindingWins() async throws {
        let tracker = Tracker()
        let bound = tracker.enriched(by: Enricher { $0[ScreenKey.self] = "Bound" })
        let sut = Tracker.viewDefault(environment: [:])
        let viewCopy = sut.enriched(by: Enricher { $0[ScreenKey.self] = ($0[ScreenKey.self] ?? "") + "/View" })
        let expected = [1, 2, 3, 4]
        let expectedScreens: [String?] = ["Bound", "Bound/View", "Bound/View", "/View"]

        await withTracker(bound) {
            withTracker(sut) {
                Tracker.current.track(Tapped(number: 1))
            }
            withTracker(viewCopy) {
                Tracker.current.track(Tapped(number: 2))
            }
            await withTracker(viewCopy) { () async in
                await Task.yield()
                Tracker.current.track(Tapped(number: 3))
            }
        }
        withTracker(tracker) {
            withTracker(viewCopy) {
                Tracker.current.track(Tapped(number: 4))
            }
        }
        await tracker.finish()

        var actual: [Int] = []
        var actualScreens: [String?] = []
        for await record in tracker.records {
            actual.append((record.event as? Tapped)?.number ?? -1)
            actualScreens.append(record.context[ScreenKey.self])
        }
        #expect(actual == expected)
        #expect(actualScreens == expectedScreens)
    }

    @Test("withTracker given a never-set view tracker with nothing bound binds it as it is, so it still drops with nothing bootstrapped")
    func bindingWithNothingBound() async {
        let tracker = Tracker()
        let sut = Tracker.viewDefault(environment: [:])
        let expected = 0

        withTracker(sut) {
            Tracker.current.track(Tapped(number: 1))
        }
        await tracker.finish()

        let actual = withTracker(sut) { Tracker.current.isNoOp }
        var count = 0
        for await _ in tracker.records {
            count += 1
        }
        #expect(!actual)
        #expect(count == expected)
    }

    @Test("In a SwiftUI preview, XCODE_RUNNING_FOR_PREVIEWS set to 1, a never-set view tracker is a no-op tracker")
    func previewIsNoOp() {
        let environment = ["XCODE_RUNNING_FOR_PREVIEWS": "1"]
        let sut = Tracker.viewDefault(environment: environment)

        let actual = sut.isNoOp

        #expect(actual)
    }

    @Test("XCODE_RUNNING_FOR_PREVIEWS set to anything but 1 isn't a preview: the never-set view tracker isn't a no-op tracker")
    func otherPreviewValues() {
        let values = ["0", "", "true", "11"]

        let actual = values.map { Tracker.viewDefault(environment: ["XCODE_RUNNING_FOR_PREVIEWS": $0]).isNoOp }

        #expect(actual == [false, false, false, false])
    }

    @Test("The process's never-set view tracker is the one its environment gives, outside a preview here")
    func processDefault() {
        let sut = Tracker.viewDefault

        let actual = sut.isNoOp

        #expect(!actual)
    }

    @Test("With nothing bootstrapped, a never-set view tracker, its enriched copy and Tracker.current inside withTracker given it drop every event without trapping")
    func dropsWithoutBootstrap() async {
        let sut = Tracker.viewDefault(environment: [:])
        let expected = 0

        sut.track(Tapped(number: 1))
        sut.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" }).track(Tapped(number: 2))
        withTracker(sut) {
            Tracker.current.track(Tapped(number: 3))
        }
        await sut.flush()
        await sut.finish()

        var actual = 0
        for await _ in sut.records {
            actual += 1
        }
        var rejections = sut.rejectionReports.makeAsyncIterator()
        var samplingDrops = sut.samplingDropReports.makeAsyncIterator()
        #expect(actual == expected)
        #expect(await rejections.next() == nil)
        #expect(await samplingDrops.next() == nil)
    }
}
