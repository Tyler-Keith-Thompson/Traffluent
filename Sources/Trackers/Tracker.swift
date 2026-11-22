public import Events
public import Foundation
import Instrumentation
import Logging

/// What app code tracks events with: it records each event, with the time, the caller's source
/// location and the task's context, as one of its ``records``.
///
/// A tracker is a value. Build one where the app starts, start delivering its records, and either
/// pass the tracker down or bind it to a task with `withTracker` and read it anywhere inside with
/// ``current``:
///
/// ```swift
/// let tracker = Tracker()
/// let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
/// withTracker(tracker) {
///     Tracker.current.track(SignedUp(plan: "pro"))
/// }
/// tracker.finish()
/// try await delivery.execute()
/// ```
///
/// Copies share one stream of records. A binding reaches the work run inside `withTracker`, and
/// the child tasks it starts, but not callbacks a framework runs on tasks of its own, such as a
/// UI framework's button actions: pass those a tracker.
///
/// Records live in memory only. Records not yet delivered are lost if the process exits.
public struct Tracker: Sendable {
    // An enum of what can back a tracker, so a no-op tracker is a case rather than an optional
    // subscription that every call checks.
    enum Backing: Sendable {
        case subscription(Subscription)
        case none
    }

    let backing: Backing
    private let enrichers: [Enricher]
    private let now: @Sendable () -> Date

    /// A tracker recording every event it tracks.
    ///
    /// - Parameters:
    ///   - enrichers: What each event's context gains as it is tracked, applied in order.
    ///   - now: The wall-clock time each event is stamped with when it is tracked.
    public init(
        enrichers: [Enricher] = [],
        // The library takes its dependencies as parameters rather than through a DI container's
        // registrations, so that adopters don't need the DI framework.
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.init(backing: .subscription(Subscription()), enrichers: enrichers, now: now)
    }

    private init(backing: Backing, enrichers: [Enricher], now: @escaping @Sendable () -> Date) {
        self.backing = backing
        self.enrichers = enrichers
        self.now = now
    }

    /// A tracker that drops every event, logging each one at debug level. Its ``records`` are
    /// empty.
    public static let noOp = Tracker(backing: .none, enrichers: [], now: { Date.now })

    /// The tracker bound to the current task by the nearest enclosing `withTracker`, or
    /// ``noOp`` when none is.
    public static var current: Tracker {
        bound ?? .noOp
    }

    @TaskLocal static var bound: Tracker?

    private static let logger = Logger(label: "Trackers.Tracker")

    /// The records of the events this tracker tracks, for a delivery to read.
    public var records: Records {
        Records(backing: backing)
    }

    /// Records `event`, with the current wall-clock time, the caller's source location and the
    /// task's `ServiceContext` as the enrichers extend it.
    ///
    /// Returns at once, from any thread; whatever reads ``records`` receives the record. An event
    /// tracked after ``finish()`` is dropped. A ``noOp`` tracker drops the event and logs it at
    /// debug level, so a missing `withTracker` shows up in the logs rather than passing silently.
    ///
    /// - Parameters:
    ///   - event: The event to track.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    public func track<E: Event>(
        _ event: E,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        switch backing {
        case .subscription(let subscription):
            let timestamp = now()
            var context = ServiceContext.current ?? .topLevel
            for enricher in enrichers {
                enricher(&context)
            }
            subscription.send(EventRecord(event: event, timestamp: timestamp, sourceLocation: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column), context: context))
        case .none:
            Self.logger.debug("Dropped \(E.name) tracked at \(fileID):\(line): no tracker is bound")
        }
    }

    /// Ends tracking: ``records`` ends after the records already tracked, so a delivery sends
    /// what is still pending and completes. Events tracked afterwards are dropped.
    public func finish() {
        guard case .subscription(let subscription) = backing else { return }
        subscription.finish()
    }
}
