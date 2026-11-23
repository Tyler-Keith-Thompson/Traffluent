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
/// the order events were tracked: the constraints' check, the enrichers, the samplers, the consent,
/// a store's writes, and publishing to ``records``. No API runs that work on a caller's thread. ``flush()`` waits for the worker to
/// catch up; ``finish()`` does too, then ends the records.
///
/// Tracked events wait in memory, without a bound, until the worker reaches them. The queue
/// can't be bounded without losing something it mustn't: it also carries consent decisions and
/// the waits of ``flush()``, and `track` can't wait for room without blocking its caller.
///
/// Without a store, records live in memory only, and records not yet delivered are lost if the
/// process exits. A tracker given a `RecordStore` (``init(store:consent:enrichers:samplers:samplingSeed:now:)``)
/// delivers what the store kept from earlier runs first, and writes each record to it once the
/// worker reaches it: a record is durable from then on, and one tracked moments before the
/// process is killed, not yet reached, is lost.
///
/// A tracker given ``Sampler``s keeps a seeded fraction of the events they apply to, dropping the
/// rest before they are held, written or delivered and reporting them on
/// ``samplingDropReports``.
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
    // The enrichers this copy adds (`enriched(by:)`), carried with each record it tracks for the
    // worker to run: `track` only captures them, so no enricher runs on the caller.
    private let scopedEnrichers: [Enricher]

    /// A tracker recording every event it tracks, or, given `consent`, every event it consents to,
    /// and, given `samplers`, the fraction of them they keep.
    ///
    /// - Parameters:
    ///   - consent: The user's consent, which each event's category must have before it is
    ///     delivered; `nil`, every event delivered, by default.
    ///   - enrichers: What each event's context gains, applied in order by the tracker's worker.
    ///   - samplers: Which events, or groups of events, to keep a fraction of, decided by the
    ///     tracker's worker after the enrichers; none by default, so every event is kept.
    ///   - samplingSeed: The seed the samplers' decisions come from: fix it and which events are
    ///     kept is fixed too. Drawn from the system's random number generator once, as the tracker
    ///     is made, by default. Fix it only in tests and replays: every launch with the same seed
    ///     makes the same decision for its first matching event, its second and so on, so a
    ///     fixed seed shipped to every device keeps the same events everywhere rather than the
    ///     sampler's rate of them.
    ///   - now: The wall-clock time each event is stamped with when it is tracked. It runs on the
    ///     tracking caller's thread, so keep it fast.
    public init(
        consent: Consent? = nil,
        enrichers: [Enricher] = [],
        samplers: [Sampler] = [],
        samplingSeed: UInt64 = .random(in: .min ... .max),
        // The library takes its dependencies as parameters rather than through a DI container's
        // registrations, so that adopters don't need the DI framework.
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.init(backing: .intake(Intake(store: nil, consent: consent, enrichers: enrichers, samplers: samplers, samplingSeed: samplingSeed)), now: now)
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
    /// Given `samplers`, a record they drop is never written. A record the store recovered was
    /// sampled in the run that wrote it, so it isn't sampled again.
    ///
    /// - Parameters:
    ///   - store: Where each record is kept until it is delivered.
    ///   - consent: The user's consent, which each event's category must have before it is
    ///     written and delivered; `nil`, every event delivered, by default.
    ///   - enrichers: What each event's context gains, applied in order by the tracker's worker.
    ///   - samplers: Which events, or groups of events, to keep a fraction of, decided by the
    ///     tracker's worker after the enrichers and before the store; none by default, so every
    ///     event is kept.
    ///   - samplingSeed: The seed the samplers' decisions come from: fix it and which events are
    ///     kept is fixed too. Drawn from the system's random number generator once, as the tracker
    ///     is made, by default. Fix it only in tests and replays: every launch with the same seed
    ///     makes the same decision for its first matching event, its second and so on, so a
    ///     fixed seed shipped to every device keeps the same events everywhere rather than the
    ///     sampler's rate of them.
    ///   - now: The wall-clock time each event is stamped with when it is tracked. It runs on the
    ///     tracking caller's thread, so keep it fast.
    public init(
        store: some RecordStore,
        consent: Consent? = nil,
        enrichers: [Enricher] = [],
        samplers: [Sampler] = [],
        samplingSeed: UInt64 = .random(in: .min ... .max),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.init(backing: .intake(Intake(store: store, consent: consent, enrichers: enrichers, samplers: samplers, samplingSeed: samplingSeed)), now: now)
    }

    private init(backing: Backing, now: @escaping @Sendable () -> Date, scopedEnrichers: [Enricher] = []) {
        self.backing = backing
        self.now = now
        self.scopedEnrichers = scopedEnrichers
    }

    /// A copy of this tracker whose events' contexts `enricher` also changes, for the code it is
    /// handed to.
    ///
    /// The copy shares this tracker's records, worker and consent; only the events tracked
    /// through it are enriched. Use it where a task-local `ServiceContext` doesn't reach, such as
    /// a UI framework's button actions: hand the part of the app a screen owns a tracker enriched
    /// with that screen.
    ///
    /// ```swift
    /// let checkout = tracker.enriched(by: Enricher { $0[ScreenKey.self] = "Checkout" })
    /// checkout.track(SignedUp(plan: "pro"))  // its record's context[ScreenKey.self] is "Checkout"
    /// ```
    ///
    /// The tracker's worker runs `enricher`, never the tracking caller, on the context `track`
    /// took and before the enrichers the tracker was built with, which see what it set. Enriching
    /// a copy again runs the new enricher after the copy's, so the newest sets a key last. A
    /// ``noOp`` tracker's copy drops every event too.
    ///
    /// - Parameter enricher: What each event tracked through the copy adds to its context.
    /// - Returns: A tracker that shares this one's records and enriches its events with `enricher`.
    public func enriched(by enricher: Enricher) -> Tracker {
        Tracker(backing: backing, now: now, scopedEnrichers: scopedEnrichers + [enricher])
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

    /// The store the tracker's worker writes each record to, if it was given one; `nil` for a
    /// ``noOp`` tracker.
    ///
    /// Package-wide, so a module that hooks the app's lifecycle can make the records durable
    /// (`synchronize()`) without the app passing the store a second time, and getting it wrong.
    package var store: (any RecordStore)? {
        switch backing {
        case .intake(let intake):
            intake.store
        case .none:
            nil
        }
    }

    /// A report of each event the tracker rejected because a property broke a constraint declared
    /// on it, in the order the rejections happen.
    ///
    /// The tracker's worker checks each event's `constraintViolation()` before anything else, so a
    /// rejected event is never enriched, held by a consent, written to a store or delivered. A
    /// record a store recovered is checked too, and one rejected is forgotten by the store. In
    /// debug builds each rejection is also logged at error level.
    ///
    /// Reports wait until they are read, merged: a rejection joins the waiting report of the same
    /// event, property and keyword, adding to its count and widening its timestamps. So the
    /// reports waiting unread are at most one per constraint the app declares, however many events
    /// break them. Copies of a tracker share one sequence, which has one consumer and ends once the
    /// tracker has finished. A ``noOp`` tracker's is empty.
    public var rejectionReports: AsyncStream<RejectionReport> {
        switch backing {
        case .intake(let intake):
            intake.rejectionReports
        case .none:
            AsyncStream { $0.finish() }
        }
    }

    /// A report of each event the tracker's ``Sampler``s dropped, in the order the drops happen.
    ///
    /// The tracker's worker samples each record after its enrichers and before the consent, so a
    /// dropped record is never held, written to a store or delivered. Records a store recovered
    /// aren't sampled again.
    ///
    /// Reports wait until they are read, merged: a drop joins the waiting report of the same
    /// event, adding to its count and widening its timestamps. So the reports waiting unread are at
    /// most one per event type, however many events are dropped. Copies of a tracker share one
    /// sequence, which has one consumer and ends once the tracker has finished. A ``noOp``
    /// tracker's is empty.
    public var samplingDropReports: AsyncStream<SamplingDropReport> {
        switch backing {
        case .intake(let intake):
            intake.samplingDropReports
        case .none:
            AsyncStream { $0.finish() }
        }
    }

    /// Records `event`, with the current wall-clock time, the caller's source location and the
    /// task's `ServiceContext` as the enrichers extend it.
    ///
    /// Returns at once, from any thread, having only queued the event: the tracker's worker
    /// makes its record, with a new identifier (`EventRecord.id`), checks its constraints, rejecting it on ``rejectionReports`` if it breaks one, runs the
    /// enrichers, on the context captured here, then the samplers, dropping it on
    /// ``samplingDropReports`` if one leaves it out, then gates the record by its consent,
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
            let entry = Intake.Entry.track(
                event: event,
                timestamp: now(),
                sourceLocation: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column),
                context: ServiceContext.current ?? .topLevel,
                enrichers: scopedEnrichers
            )
            guard intake.enqueue(entry) else {
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
