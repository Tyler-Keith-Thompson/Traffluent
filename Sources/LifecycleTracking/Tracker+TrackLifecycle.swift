import Events
public import Foundation
public import Trackers

extension Tracker {
    /// Tracks the app's lifecycle through this tracker until the observation it returns is
    /// cancelled, finished or released: ``ApplicationInstalled`` or ``ApplicationUpdated`` and
    /// ``ApplicationOpened`` as it starts, then ``ApplicationBackgrounded``,
    /// ``ApplicationOpened`` again and ``ApplicationTerminated`` as the app moves.
    ///
    /// Nothing is tracked until this is called. Call it as the app launches, such as in its
    /// application delegate's `application(_:didFinishLaunchingWithOptions:)`, and keep what it
    /// returns:
    ///
    /// ```swift
    /// lifecycle = tracker.trackLifecycle()
    /// ```
    ///
    /// As it starts, it compares `version` with the one `versionStore` saved: none tracks an
    /// install, another an update, the same neither; it then saves `version`. Then it tracks an
    /// open, not from the background. After that, each transition tracks once, however many times
    /// it is reported:
    ///
    /// - iOS, iPadOS, tvOS, visionOS and Mac Catalyst: `UIApplication`'s notifications. Entering
    ///   the background tracks ``ApplicationBackgrounded``, returning to the foreground
    ///   ``ApplicationOpened`` from the background, and terminating ``ApplicationTerminated``.
    ///   A scene-based app gets them once for the whole app, not per scene.
    /// - watchOS: `WKApplication`'s, without termination, which watchOS doesn't report.
    /// - macOS: `NSApplication`'s. Another app becoming active counts as the background, this
    ///   one becoming active again as the foreground.
    /// - Linux: no notifications; ``LifecycleObservation/finish()`` tracks the termination.
    ///
    /// Leaving the foreground, it also makes the tracker's records durable: it waits for the
    /// tracker's worker to write every record tracked so far to the tracker's store, then calls
    /// the store's `synchronize()`. A delivery batched with ``LifecycleBatchStrategy`` sends what
    /// is pending as it reads the ``ApplicationBackgrounded`` record. A notification's handler only
    /// hands the transition on; the tracking, the version store and the store's work run on a
    /// task of their own, never on the thread that posted it. Where the system suspends an app in the
    /// background (all but macOS and Mac Catalyst), the handler asks it for background time
    /// (`ProcessInfo.performExpiringActivity`), held until the records are durable. A termination's records are made durable the same way, without
    /// holding the main thread up: what the process doesn't finish before it exits is what the
    /// tracker's documented loss window takes.
    ///
    /// It keeps no state outside what it returns. Two calls observe twice, so call it once per
    /// tracker.
    ///
    /// - Parameters:
    ///   - kinds: The kinds of event to track; every kind by default. Leaving one out doesn't
    ///     stop the rest of the work: the version is still saved, and the records still made
    ///     durable on backgrounding.
    ///   - version: The version the app runs at now; the bundle's `CFBundleShortVersionString`
    ///     by default. `nil` tracks neither installs nor updates, and saves nothing.
    ///   - versionStore: Where the version is kept from one launch to the next; a
    ///     ``FileVersionStore`` in `SegmentStore.defaultDirectory` by default.
    ///   - notificationCenter: Where the platform posts its lifecycle notifications; the default
    ///     center by default.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    /// - Returns: The observation, which tracks until it is cancelled, finished or released.
    public func trackLifecycle(
        kinds: Set<LifecycleObservation.Kind> = Set(LifecycleObservation.Kind.allCases),
        version: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        versionStore: some VersionStore = FileVersionStore(),
        notificationCenter: NotificationCenter = .default,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) -> LifecycleObservation {
        let worker = LifecycleWorker(
            tracker: self,
            kinds: kinds,
            version: version,
            versionStore: versionStore,
            callSite: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column)
        )
        return LifecycleObservation(monitor: LifecycleMonitor(worker: worker, center: notificationCenter))
    }
}
