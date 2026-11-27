public import AsyncQueues
public import Events
public import Foundation
internal import Instrumentation
import Logging
public import Persistence
internal import Synchronization

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
/// the child tasks it starts, but not a detached task or callbacks a framework runs on tasks of
/// its own, such as a UI framework's button actions: pass those a tracker, or make the app's
/// tracker the process's default once, at launch, with ``bootstrap(_:)``, which ``current`` falls
/// back to wherever no tracker is bound.
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
    // intake that every call checks. `unbound` drops like `none` but warns: it is what
    // `Tracker.current` gives with nothing bound, where a drop means a binding that doesn't reach
    // the task, while `noOp` is also a deliberate default (a SwiftUI preview's environment).
    // `unset` is a view's tracker that was never set: it stands for the bootstrapped tracker, or
    // `unbound` without one, looked up each time it is used rather than when the view reads it,
    // as a view can read its environment before the app bootstraps.
    enum Backing: Sendable {
        case intake(Intake)
        case none
        case unbound
        case unset
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

    /// The tracker of a view whose tracker was never set: SwiftUI's environment without
    /// `tracker(_:)`, a UIKit trait collection without one, an AppKit view below no provider.
    ///
    /// Package-wide, for the UI modules' defaults: ``viewDefault(environment:)`` of the process's
    /// environment variables, read once.
    package static let viewDefault = viewDefault(environment: ProcessInfo.processInfo.environment)

    /// The tracker of a view whose tracker was never set, in a process whose environment
    /// variables are `environment`.
    ///
    /// In a SwiftUI preview (`XCODE_RUNNING_FOR_PREVIEWS` is `1`) it is ``noOp``, so a preview
    /// shown without a tracker drops what it tracks quietly. Anywhere else it behaves as
    /// ``current`` does with nothing bound, deciding each time it is used rather than now: it
    /// tracks through the tracker ``bootstrap(_:)`` made the process's default, and without one
    /// drops each event, logging the first from each call site at warning level. Its copies made
    /// by ``enriched(by:)`` reach the bootstrapped tracker too, adding what they enrich. Code
    /// inside `withTracker` given it tracks through the tracker already bound around that call, if
    /// any, and otherwise through the bootstrapped tracker.
    ///
    /// Package-wide, so the UI modules share one default, which their tests can make for a
    /// preview's environment.
    ///
    /// - Parameter environment: The process's environment variables.
    /// - Returns: ``noOp`` in a preview, and otherwise a tracker standing for the bootstrapped one.
    package static func viewDefault(environment: [String: String]) -> Tracker {
        // The preview check is in the default rather than in the warning: a preview's view
        // behaves as a view given `noOp` does (it waits for a tracker, quietly), and the warning
        // stays `current`'s alone, knowing nothing of previews.
        environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ? .noOp : unset
    }

    /// The tracker bound to the current task by the nearest enclosing `withTracker`; with none
    /// bound, the one ``bootstrap(_:)`` made the process's default; and with neither, one that
    /// drops every event, as ``noOp`` does.
    ///
    /// A binding reaches the work inside `withTracker` and the child tasks it starts. A detached
    /// task (`Task.detached`) and a callback a framework runs on a task of its own get no
    /// binding, so `Tracker.current` there is the bootstrapped tracker. Without one it drops what
    /// it tracks: bootstrap the app's tracker at launch, or hand that code a tracker value. The
    /// first event dropped at each call site is logged at warning level, and later ones from that
    /// call site at debug level.
    public static var current: Tracker {
        // The bootstrapped tracker is read only where nothing is bound, so code inside
        // `withTracker` takes no lock.
        bound ?? bootstrapped.withLock { $0 } ?? .unbound
    }

    /// Makes `tracker` the process's default: what ``current`` gives wherever no `withTracker`
    /// binding reaches, such as a detached task or a framework's callback.
    ///
    /// Call it once, as the app starts (in a SwiftUI `App`'s `init()`, say), before anything
    /// tracks through ``current``. A `withTracker` binding still wins inside its scope. The default
    /// can be set only once and never replaced or cleared, so code that reads ``current`` from
    /// another thread never sees it change. The process holds the tracker from then on, so it
    /// doesn't finish when the app's own copies are released; ``finish()`` still ends it.
    ///
    /// ```swift
    /// let tracker = Tracker()
    /// try Tracker.bootstrap(tracker)
    /// Task.detached {
    ///     Tracker.current.track(SignedUp(plan: "pro"))  // tracked by tracker
    /// }
    /// ```
    ///
    /// - Parameter tracker: The tracker ``current`` falls back to.
    /// - Throws: ``TrackerAlreadyBootstrapped`` when a tracker has been bootstrapped already; the
    ///   first one stays the default.
    public static func bootstrap(_ tracker: Tracker) throws(TrackerAlreadyBootstrapped) {
        try bootstrapped.withLock { (bootstrapped: inout Tracker?) throws(TrackerAlreadyBootstrapped) in
            guard bootstrapped == nil else { throw TrackerAlreadyBootstrapped() }
            bootstrapped = tracker
        }
    }

    @TaskLocal static var bound: Tracker?

    // The process's default tracker, set once by `bootstrap` and never cleared (charter N2's one
    // exception, as swift-log's `LoggingSystem.bootstrap`). A Mutex rather than an Atomic: a
    // `Tracker` is a struct of class references and a closure, which no `Atomic` can hold, and
    // `AtomicLazyReference` would need it boxed in a class of its own, an allocation and an
    // indirection to save an uncontended lock that `current` takes only where nothing is bound.
    private static let bootstrapped = Mutex<Tracker?>(nil)

    /// What ``current`` gives with no tracker bound: a no-op tracker whose drops warn.
    private static let unbound = Tracker(backing: .unbound, now: { Date.now })

    /// A view's tracker that was never set, outside a preview: the bootstrapped tracker, looked up
    /// each time it is used.
    private static let unset = Tracker(backing: .unset, now: { Date.now })

    /// What an `unset` tracker stands for now: the bootstrapped tracker, or ``unbound`` without
    /// one, with this copy's enrichers run after the bootstrapped tracker's copy's own.
    private var resolved: Tracker {
        guard let target = Self.bootstrapped.withLock({ $0 }) else {
            return Tracker(backing: .unbound, now: now, scopedEnrichers: scopedEnrichers)
        }
        switch target.backing {
        case .intake, .none:
            return Tracker(backing: target.backing, now: target.now, scopedEnrichers: Self.enrichers(target.scopedEnrichers, then: scopedEnrichers))
        case .unbound, .unset:
            // A view's default bootstrapped as the process's stands for nothing but itself, so it
            // drops as `current` does with nothing bootstrapped, rather than look itself up again.
            return Tracker(backing: .unbound, now: now, scopedEnrichers: scopedEnrichers)
        }
    }

    /// `first`, then `second`: the enrichers of the tracker an `unset` copy stands for, then the
    /// copy's own.
    // Runs on every event tracked through an `unset` tracker, so it hands back one side as it is
    // when the other is empty, as one nearly always is, rather than allocate an array per event.
    private static func enrichers(_ first: [Enricher], then second: [Enricher]) -> [Enricher] {
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + second
    }

    /// What `withTracker` binds for this tracker: this tracker, except that an `unset` one given
    /// inside another binding stands for the bound tracker, with its own enrichers after the bound
    /// tracker's, so a view whose tracker was never set doesn't hide a test's or a caller's binding.
    ///
    /// - Parameter bound: The tracker bound where `withTracker` is called, if any.
    /// - Returns: The tracker to bind.
    func binding(over bound: Tracker?) -> Tracker {
        guard case .unset = backing, let bound else { return self }
        return Tracker(backing: bound.backing, now: bound.now, scopedEnrichers: Self.enrichers(bound.scopedEnrichers, then: scopedEnrichers))
    }

    private static let logger = Logger(label: "Trackers.Tracker")

    // The call sites that have warned of an event tracked with no tracker bound, so a loop
    // tracking through a missing binding warns once per call site rather than once per event:
    // the warning is built and written on the tracking caller, and warning level is on by
    // default. Per call site rather than once per process, so every missing binding shows up. A
    // Mutex rather than an actor: `track` is synchronous and must not wait. It grows by one entry
    // per call site, which the program's source bounds.
    private static let warnedUnboundCallSites = Mutex<Set<UnboundCallSite>>([])

    /// The records of the events this tracker tracks, for a delivery to read.
    ///
    /// A view's tracker that was never set gives the records of the tracker bootstrapped when this
    /// is read, and none without one.
    public var records: Records {
        switch backing {
        case .intake(let intake):
            Records(subscription: intake.subscription)
        case .none, .unbound:
            Records(subscription: nil)
        case .unset:
            resolved.records
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
        case .none, .unbound:
            nil
        case .unset:
            resolved.store
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
    /// break them. Copies of a tracker share one sequence, which ends once the tracker has
    /// finished and every report has been read. A ``noOp`` tracker's is empty.
    ///
    /// One task reads the reports at a time. The first iterator to read holds them until its
    /// iteration ends or it is released; a second reader meanwhile waits its turn, logging a
    /// warning once, then reads on from the next report, so the first gets every report in order.
    /// A reader cancelled while it waits returns `nil`.
    public var rejectionReports: AsyncQueue<RejectionReport> {
        switch backing {
        case .intake(let intake):
            intake.rejectionReports
        case .none, .unbound:
            .finished(name: "a tracker's rejection reports")
        case .unset:
            resolved.rejectionReports
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
    /// sequence, which ends once the tracker has finished and every report has been read. A
    /// ``noOp`` tracker's is empty.
    ///
    /// One task reads the reports at a time. The first iterator to read holds them until its
    /// iteration ends or it is released; a second reader meanwhile waits its turn, logging a
    /// warning once, then reads on from the next report, so the first gets every report in order.
    /// A reader cancelled while it waits returns `nil`.
    public var samplingDropReports: AsyncQueue<SamplingDropReport> {
        switch backing {
        case .intake(let intake):
            intake.samplingDropReports
        case .none, .unbound:
            .finished(name: "a tracker's sampling drop reports")
        case .unset:
            resolved.samplingDropReports
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
    /// logs it at debug level. So does ``current`` with no tracker bound or bootstrapped, except
    /// that the first event it drops at each call site is logged at warning level, so a missing
    /// `withTracker` shows up in the logs rather than passing silently. A view whose tracker was
    /// never set tracks as ``current`` does with nothing bound, through the tracker bootstrapped by
    /// the time it tracks.
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
            Self.logger.debug("Dropped \(E.name) tracked at \(fileID):\(line): the tracker is Tracker.noOp")
        case .unbound:
            // A drop path too. The first drop at a call site warns, as it most likely means a
            // `withTracker` that doesn't reach this task; the rest log at debug level, so a hot
            // loop pays one lock and set lookup per event rather than a warning.
            let callSite = UnboundCallSite(fileID: fileID, line: line, column: column)
            let isFirst = Self.warnedUnboundCallSites.withLock { $0.insert(callSite).inserted }
            if isFirst {
                Self.logger.warning("Dropped \(E.name) tracked at \(fileID):\(line): no tracker is bound to this task or set on the view it was tracked from, and none is bootstrapped. withTracker doesn't reach a detached task or a framework's callback; pass it a tracker, set one at the root of the views, or bootstrap the app's with Tracker.bootstrap")
            } else {
                Self.logger.debug("Dropped \(E.name) tracked at \(fileID):\(line): no tracker is bound")
            }
        case .unset:
            // Looked up now, not when the view read its tracker, so a view that read it before the
            // app bootstrapped still reaches the bootstrapped tracker; without one this takes the
            // `unbound` path above, warning once per call site.
            resolved.track(event, file: file, fileID: fileID, function: function, line: line, column: column)
        }
    }

    /// Whether this tracker drops every event wherever it is used: ``noOp``, ``current`` with no
    /// tracker bound or bootstrapped, or a copy of either made by ``enriched(by:)``.
    ///
    /// ``viewDefault`` outside a preview isn't, even with nothing bootstrapped or with ``noOp``
    /// bootstrapped: it tracks through the tracker bootstrapped by the time it is used, and without
    /// one warns of what it drops.
    ///
    /// Package-wide, so a UI module whose views can appear before their tracker reaches them can
    /// wait for it rather than track the appearance into nothing. A view whose tracker was never
    /// set doesn't wait: it tracks as ``current`` does, so a forgotten tracker shows up in the
    /// logs rather than as a view that never tracks.
    package var isNoOp: Bool {
        switch backing {
        case .intake:
            return false
        case .unset:
            // Even with nothing bootstrapped yet: the app may bootstrap before the view tracks,
            // and without a bootstrap the view should warn as it tracks, not wait in silence.
            return false
        case .none, .unbound:
            return true
        }
    }

    /// Waits until the tracker's worker has handled every event tracked, and every consent
    /// decision made, before the call: each record is written to the store, if any, and
    /// published to ``records``, or held or dropped by the consent.
    ///
    /// Call it where the app must know its records are durable, such as as it moves to the
    /// background, before the store's `synchronize()`. Returns at once for a ``noOp`` tracker.
    public func flush() async {
        switch backing {
        case .intake(let intake):
            await intake.flush()
        case .none, .unbound:
            return
        case .unset:
            await resolved.flush()
        }
    }

    /// Ends tracking: waits for the worker to handle every event already tracked, then ends
    /// ``records`` after them, so a delivery sends what is still pending and completes. Events
    /// tracked afterwards are dropped.
    ///
    /// With a consent, the records it holds for this tracker can't be delivered any more: those
    /// held in memory only are dropped and reported on ``Consent/dropReports``; those a store
    /// keeps stay there for a later launch. A tracker whose every copy is released finishes the
    /// same way, without anyone waiting.
    ///
    /// A view's tracker that was never set stands for the tracker bootstrapped when this is called,
    /// so finishing it ends the bootstrapped tracker.
    public func finish() async {
        switch backing {
        case .intake(let intake):
            await intake.finish()
        case .none, .unbound:
            return
        case .unset:
            await resolved.finish()
        }
    }
}

/// A place `track` was called from, for warning once per call site of tracking with no tracker
/// bound.
private struct UnboundCallSite: Hashable {
    let fileID: String
    let line: Int
    let column: Int
}
