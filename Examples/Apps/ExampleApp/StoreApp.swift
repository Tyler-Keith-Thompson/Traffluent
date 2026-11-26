import Foundation
import LifecycleTracking
import OSLog
import Persistence
import StoreAnalytics
import StoreViews
import SwiftUI
import SwiftUITracking

/// The store app, one source for every Apple platform, and its composition root.
///
/// As it launches, it restores the shopper's consent, builds the analytics, turns on lifecycle
/// tracking and starts the delivery, which runs for the life of the app. It logs every drop
/// report. Then it sets the tracker in the environment at the root of the views, and, where
/// UIKit has window scenes, as the scene's trait, turning on automatic screen and control
/// tracking there.
@main
struct StoreApp: App {
    private let preferences: ConsentPreferences
    private let analytics: StoreAnalytics
    // Tracks the lifecycle only while it is held, so the app keeps it.
    private let lifecycle: LifecycleObservation

    private static let logger = Logger(subsystem: "com.example.traffluent", category: "StoreApp")

    // The example server (`just serve-example`); a malformed literal would become logged drops.
    private static let collector = URL(string: "http://127.0.0.1:8080/v1/batches") ?? URL(fileURLWithPath: "/")

    init() {
        let directory = SegmentStore.defaultDirectory
        preferences = ConsentPreferences(file: URL(fileURLWithPath: directory.appending("consent.json").string))
        analytics = StoreAnalytics(collector: Self.collector, consent: preferences.consent, directory: directory)
        // On a first launch, ApplicationInstalled and ApplicationOpened are tracked before the
        // shopper answers the consent prompt, so they are held in memory only, and lost if the
        // shopper quits before answering.
        lifecycle = analytics.tracker.trackLifecycle(versionStore: FileVersionStore(directory: directory))

        // Runs for the life of the app: nothing cancels it, so it throws only when the store's
        // tracking plan is invalid, after which nothing is delivered; that is logged.
        Task { [analytics] in
            do {
                try await analytics.deliver()
            } catch {
                Self.logger.error("Delivery stopped: \(String(describing: error), privacy: .public)")
            }
        }
        let drops = analytics.drops
        Task {
            for await drop in drops {
                // A drop names events and counts records, never what a shopper entered.
                Self.logger.warning("\(drop, privacy: .public)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            StoreView(preferences: preferences)
                #if canImport(UIKit) && !os(watchOS)
                    .trackWindowSceneAutomatically(analytics.tracker)
                #endif
                .tracker(analytics.tracker)
        }
    }
}
