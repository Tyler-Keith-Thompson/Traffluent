// The landing page's (Sources/Traffluent/Traffluent.docc/Traffluent.md) App and view, verbatim.
// Its App runs only on the Mac, where SwiftUI is, and in an exit test, in a file of its own: its
// body runs in a child process, which iOS, tvOS, watchOS and visionOS cannot start. A child
// process because the App's init bootstraps its tracker, which stays the process's default for
// good, so bootstrapping in the test process would change `Tracker.current` for every other test
// running beside it.
#if os(macOS)
import Foundation
import SwiftUI
import Testing
import Traffluent

// The page's `savedDecisions` and `startAnalytics(consent:)`. The function's body is in
// TraffluentExamplesTests.swift; this one builds a tracker with no store or delivery, so the
// child process writes nothing and sends nothing.
private let savedDecisions: [ConsentCategory: ConsentStatus] = [.analytics: .granted]

private func startAnalytics(consent: Consent) throws -> Tracker {
    Tracker(consent: consent)
}

@Suite("Landing page examples: the App", .timeLimit(.minutes(1)))
struct TraffluentExamplesExitTests {
    @Event(name: "product_added_to_cart")
    struct ProductAddedToCart {
        var productID: String
        @Constrained(.minimum(1), .maximum(10))
        var quantity: Int
    }

    // The page marks it `@main`, which a test bundle, with an entry point of its own, can't.
    struct StoreApp: App {
        let tracker: Tracker

        init() {
            do {
                // The user's earlier decisions, which the app saved; undecided categories wait in memory.
                let tracker = try startAnalytics(consent: Consent(savedDecisions))
                // `Tracker.current` falls back to it where nothing else reaches, such as a detached task.
                try Tracker.bootstrap(tracker)
                self.tracker = tracker
            } catch {
                print("Analytics are off: \(error)")
                tracker = .noOp
            }
        }

        var body: some Scene {
            WindowGroup {
                CartView()
                    .tracker(tracker)
            }
        }
    }

    struct CartView: View {
        @Environment(\.tracker) private var tracker

        var body: some View {
            Button("Add to Cart") {
                tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 1))
            }
        }
    }

    @Test("The App's init bootstraps its tracker, so a detached task's Tracker.current tracks through it")
    func appBootstrapsItsTracker() async {
        await #expect(processExitsWith: .success) {
            let tracker = await MainActor.run { StoreApp().tracker }
            let expected = [1]
            let expectedError: TrackerAlreadyBootstrapped? = TrackerAlreadyBootstrapped()

            await Task.detached {
                Tracker.current.track(ProductAddedToCart(productID: "canvas-tote", quantity: 1))
            }.value
            let actualError: TrackerAlreadyBootstrapped?
            do throws(TrackerAlreadyBootstrapped) {
                try Tracker.bootstrap(Tracker())
                actualError = nil
            } catch {
                actualError = error
            }
            await tracker.finish()

            var actual: [Int] = []
            for await record in tracker.records {
                actual.append((record.event as? ProductAddedToCart)?.quantity ?? 0)
            }
            guard actual == expected, actualError == expectedError else { exit(EXIT_FAILURE) }
        }
    }
}
#endif
