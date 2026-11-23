public import Events
public import Foundation
import Instrumentation
import Logging
public import Persistence

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
/// await tracker.finish()
/// try await delivery.execute()
/// ```
///
/// Copies share one stream of records. A binding reaches the work run inside `withTracker`, and
/// the child tasks it starts, but not callbacks a framework runs on tasks of its own, such as a
/// UI framework's button actions: pass those a tracker.
///
/// ``track(_:file:fileID:function:line:column:)`` does nothing but accept the event, from any
/// thread: it reads the clock, captures the call site and the task's `ServiceContext`, and queues
/// them. A worker the tracker owns, which never runs on the main actor, does everything else, in
/// the order events were tracked: the enrichers, the consent, a store's writes, and publishing to
/// ``records``. No API runs that work on a caller's thread. ``flush()`` waits for the worker to
/// catch up; ``finish()`` does too, then ends the records.
///
/// Tracked events wait in memory, without a bound, until the worker reaches them. The queue
/// can't be bounded without losing something it mustn't: it also carries consent decisions and
/// the waits of ``flush()``, and `track` can't wait for room without blocking its caller.
///
/// Without a store, records live in memory only, and records not yet delivered are lost if the
/// process exits. A tracker given a `RecordStore` (``init(store:consent:enrichers:now:)``)
/// delivers what the store kept from earlier runs first, and writes each record to it once the
/// worker reaches it: a record is durable from then on, and one tracked moments before the
/// process is killed, not yet reached, is lost.
///
/// A tracker given a ``Consent`` delivers an event only once its category is granted, holding it
/// while undecided and dropping it when denied; one given none delivers every event.
public struct Tracker: Sendable {
    // An enum of what can back a tracker, so a no-op tracker is a case rather than an optional
    // intake that every call checks.
    enum Backing: Sendable {
        case intake(Intake)
        case none
    }

    let backing: Backing
    private let now: @Sendable () -> Date

    /// A tracker recording every event it tracks, or, given `consent`, every event it consents to.
    ///
    /// - Parameters:
    ///   - consent: The user's consent, which each event's category must have before it is
    ///     delivered; `nil`, every event delivered, by default.
    ///   - enrichers: What each event's context gains, applied in order by the tracker's worker.
    ///   - now: The wall-clock time each event is stamped with when it is tracked. It runs on the
    ///     tracking caller's thread, so keep it fast.
    public init(
        consent: Consent? = nil,
        enrichers: [Enricher] = [],
        // The library takes its dependencies as parameters rather than through a DI container's
        // registrations, so that adopters don't need the DI framework.
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.init(backing: .intake(Intake(store: nil, consent: consent, enrichers: enrichers)), now: now)
    }

    /// A tracker that writes every record to `store`, so records survive the app ending, and
    /// whose ``records`` start with the ones `store` kept from earlier runs.
    ///
    /// The tracker's worker writes each record as it reaches it, before publishing it to
    /// ``records``, rather than a stage reading ``records``, which runs in the delivery's task,
    /// later, perhaps after a slow batch. Given `consent`, a record is written once its category
    /// is granted, not while it is held, and the recovered records are gated again. The worker
    /// takes the recovered records from `store` before anything tracked.
    ///
    /// - Parameters:
    ///   - store: Where each record is kept until it is delivered.
    ///   - consent: The user's consent, which each event's category must have before it is
    ///     written and delivered; `nil`, every event delivered, by default.
    ///   - enrichers: What each event's context gains, applied in order by the tracker's worker.
    ///   - now: The wall-clock time each event is stamped with when it is tracked. It runs on the
    ///     tracking caller's thread, so keep it fast.
    public init(
        store: some RecordStore,
        consent: Consent? = nil,
        enrichers: [Enricher] = [],
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.init(backing: .intake(Intake(store: store, consent: consent, enrichers: enrichers)), now: now)
    }

    private init(backing: Backing, now: @escaping @Sendable () -> Date) {
        self.backing = backing
        self.now = now
    }

    /// A tracker that drops every event, logging each one at debug level. Its ``records`` are
    /// empty.
    public static let noOp = Tracker(backing: .none, now: { Date.now })

    /// The tracker bound to the current task by the nearest enclosing `withTracker`, or
    /// ``noOp`` when none is.
    public static var current: Tracker {
        bound ?? .noOp
    }

    @TaskLocal static var bound: Tracker?

    private static let logger = Logger(label: "Trackers.Tracker")

    /// The records of the events this tracker tracks, for a delivery to read.
    public var records: Records {
        switch backing {
        case .intake(let intake):
            Records(subscription: intake.subscription)
        case .none:
            Records(subscription: nil)
        }
    }

    /// Records `event`, with the current wall-clock time, the caller's source location and the
    /// task's `ServiceContext` as the enrichers extend it.
    ///
    /// Returns at once, from any thread, having only queued the event: the tracker's worker
    /// runs the enrichers, on the context captured here, then gates the record by its consent,
    /// writes it to its store and publishes it to ``records``. An event tracked after
    /// ``finish()`` is dropped and logged at debug level. A ``noOp`` tracker drops the event and
    /// logs it at debug level, so a missing `withTracker` shows up in the logs rather than passing
    /// silently.
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
        case .intake(let intake):
            let record = EventRecord(
                event: event,
                timestamp: now(),
                sourceLocation: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column),
                context: ServiceContext.current ?? .topLevel
            )
            guard intake.enqueue(.track(record)) else {
                // The one piece of work `track` does on its caller besides queuing: only on this
                // drop path, never for a delivered event, and at debug level, whose message is
                // an autoclosure built only when the level is enabled.
                Self.logger.debug("Dropped \(E.name) tracked at \(fileID):\(line): the tracker has finished")
                return
            }
        case .none:
            // As above: a drop path, logged on the caller at debug level, the message an
            // autoclosure built only when the level is enabled.
            Self.logger.debug("Dropped \(E.name) tracked at \(fileID):\(line): no tracker is bound")
        }
    }

    /// Waits until the tracker's worker has handled every event tracked, and every consent
    /// decision made, before the call: each record is written to the store, if any, and
    /// published to ``records``, or held or dropped by the consent.
    ///
    /// Call it where the app must know its records are durable, such as as it moves to the
    /// background, before the store's `synchronize()`. Returns at once for a ``noOp`` tracker.
    public func flush() async {
        guard case .intake(let intake) = backing else { return }
        await intake.flush()
    }

    /// Ends tracking: waits for the worker to handle every event already tracked, then ends
    /// ``records`` after them, so a delivery sends what is still pending and completes. Events
    /// tracked afterwards are dropped.
    ///
    /// With a consent, the records it holds for this tracker can't be delivered any more: those
    /// held in memory only are dropped and reported on ``Consent/dropReports``; those a store
    /// keeps stay there for a later launch. A tracker whose every copy is released finishes the
    /// same way, without anyone waiting.
    public func finish() async {
        guard case .intake(let intake) = backing else { return }
        await intake.finish()
    }
}
