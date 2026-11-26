import Foundation
import LifecycleTracking
import Sessions
import StandardContext
import StoreAnalytics
import StoreModel
import SystemPackage
import Trackers

/// The store's analytics without a screen, on any platform Linux included: a scripted shopping
/// trip through the app's own `StoreAnalytics`, whose collector prints each batch's body instead
/// of sending it.
///
/// The shopper allows analytics and their account, and declines marketing, so the promotion's tap
/// is never collected. The sign-up's email address is a sensitive value the collector never
/// receives. The records go through a store in a scratch directory, deleted at the end.
@main
struct CommandLineExample {
    static func main() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("CommandLineExample-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let analytics = StoreAnalytics(
            // Never contacted (the printing transport answers), so a file URL can stand in.
            collector: URL(string: "https://collector.example.com/v1/batches") ?? URL(fileURLWithPath: "/"),
            consent: Consent([.analytics: .granted, .functional: .granted, .advertising: .denied]),
            directory: directory,
            // A command-line program has no Info.plist to read its version from, and no device.
            enrichers: [
                .sessions(),
                .application(ApplicationKey.Value(bundleIdentifier: "com.example.traffluent.cli", version: "1.0.0", build: "1")),
                .operatingSystem(),
                .locale(),
            ],
            transport: PrintingTransport()
        )
        let tracker = analytics.tracker
        let lifecycle = tracker.trackLifecycle(version: "1.0.0", versionStore: InMemoryVersionStore())
        let delivery = Task { try await analytics.deliver() }

        // The cart and the account track through `Tracker.current`, which the shopping trip binds
        // to the store's tracker: a program this short needs no process-wide default.
        var cart = Cart()
        try withTracker(tracker) {
            for product in Product.catalog.prefix(1) {
                try cart.add(product, quantity: 2)
            }
            cart.apply(.springSale)
            cart.startCheckout()
            _ = cart.placeOrder(expressShipping: true)
            _ = Account.signUp(email: "shopper@example.com", plan: .plus)
        }

        // Tracks the termination, then ends the records, so the delivery sends the last batch
        // and returns.
        await lifecycle.finish()
        await tracker.finish()
        try await delivery.value
    }
}
