import Dispatch
import Foundation

/// Time the system grants the app to finish work after it leaves the foreground, held from
/// ``begin()`` until ``end()``.
///
/// On iOS, iPadOS, tvOS, watchOS and visionOS, which suspend an app in the background. A Mac app,
/// Mac Catalyst's included, isn't suspended, so there it asks for nothing.
///
/// `ProcessInfo.performExpiringActivity(withReason:using:)` rather than UIKit's
/// `beginBackgroundTask(expirationHandler:)`: it needs neither the main actor nor
/// `UIApplication.shared`, works in app extensions, and is the same call on watchOS. Its block
/// runs on a queue of its own, which waits there, never on the main thread.
struct BackgroundTime: Sendable {
    private let ended = DispatchSemaphore(value: 0)

    /// Asks for the time, which lasts until ``end()`` or until the system takes it back.
    func begin() {
        #if (os(iOS) && !targetEnvironment(macCatalyst)) || os(tvOS) || os(watchOS) || os(visionOS)
        let ended = ended
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Making analytics records durable") { expired in
            if expired {
                // The system takes the time back: the waiting call below must return now.
                ended.signal()
            } else {
                ended.wait()
            }
        }
        #endif
    }

    /// Gives the time back: the work it was held for is done.
    func end() {
        ended.signal()
    }
}
