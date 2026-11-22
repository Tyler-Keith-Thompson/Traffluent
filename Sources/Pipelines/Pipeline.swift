public import Afluent
public import Destinations
public import Events
public import Foundation

/// Records each tracked event, gathers the records into batches, and delivers every batch to
/// each of its destinations.
///
/// A pipeline is a value: build one where the app starts, run it, and pass it to what tracks
/// events. Copies share one stream of events.
///
/// ```swift
/// let pipeline = Pipeline(ConsoleDestination())
/// pipeline.track(SignedUp(plan: "pro"))
/// pipeline.finish()
/// try await pipeline.run().execute()
/// ```
///
/// Tracking stamps the event with the time and the caller's source location, and sends the record
/// through an Afluent `PassthroughSubject`. ``run()`` batches the records by the pipeline's
/// strategy and delivers each batch.
///
/// Timestamps are read from the pipeline's clock, measured from the wall-clock time when the
/// pipeline was created (its time origin): a record's timestamp is the origin plus the time the
/// clock has advanced since. They stay in order when the system's wall clock is adjusted.
public struct Pipeline: Sendable {
    // Existentials: one pipeline holds destinations of different types, and a strategy and clock
    // whose types the pipeline's own type doesn't carry, so every pipeline is a `Pipeline`.
    let destinations: [any Destination]
    package let strategy: any BatchStrategy<EventRecord>
    let subject = PassthroughSubject<EventRecord>()
    let subscription: Subscription
    let timeOrigin: Date
    let elapsed: @Sendable () -> Duration

    /// A pipeline delivering to `destinations`, every 20 events and every 30 seconds by `clock`
    /// while any are pending.
    ///
    /// - Parameters:
    ///   - destinations: Where each batch goes.
    ///   - clock: The clock timestamps are read from and the 30 seconds are measured on.
    public init(
        _ destinations: any Destination...,
        // The core takes its dependencies as parameters rather than through a DI container's
        // registrations, so that adopters don't need the DI framework.
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        self.init(
            destinations,
            clock: clock,
            strategy: EitherBatchStrategy(.count(20), .time(interval: .seconds(30), clock: clock)))
    }

    /// A pipeline delivering to `destinations`, in batches `strategy` decides.
    ///
    /// Afluent's strategies compose: `.count(_:)`, `.time(interval:clock:tolerance:)`,
    /// `.signal(_:)` and `.either(_:_:)`.
    ///
    /// - Parameters:
    ///   - destinations: Where each batch goes.
    ///   - clock: The clock timestamps are read from.
    ///   - strategy: When the pending records are delivered as a batch.
    public init(
        _ destinations: any Destination...,
        // The core takes its dependencies as parameters rather than through a DI container's
        // registrations, so that adopters don't need the DI framework.
        clock: some Clock<Duration> = ContinuousClock(),
        strategy: some BatchStrategy<EventRecord>
    ) {
        self.init(destinations, clock: clock, strategy: strategy)
    }

    private init(
        _ destinations: [any Destination], clock: some Clock<Duration>, strategy: some BatchStrategy<EventRecord>
    ) {
        self.destinations = destinations
        self.strategy = strategy
        subscription = Subscription(to: subject)
        timeOrigin = Date.now
        let start = clock.now
        elapsed = { start.duration(to: clock.now) }
    }

    /// Records `event`, with the current time and the caller's source location, for the next
    /// batch.
    ///
    /// Returns at once; ``run()`` delivers the record. An event tracked after ``finish()`` is
    /// dropped.
    ///
    /// - Parameters:
    ///   - event: The event to track.
    ///   - file: The caller's file; leave it to its default.
    ///   - fileID: The caller's module and file name; leave it to its default.
    ///   - function: The caller's enclosing declaration; leave it to its default.
    ///   - line: The caller's line; leave it to its default.
    ///   - column: The caller's column; leave it to its default.
    public func track(
        _ event: some Event,
        file: String = #file,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        let timestamp = timeOrigin.addingTimeInterval(elapsed().timeInterval)
        subject.send(EventRecord(event: event, timestamp: timestamp, sourceLocation: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column)))
    }

    /// Ends tracking: ``run()`` delivers the records still pending as a last batch, then finishes.
    public func finish() {
        subject.send(completion: .finished)
    }

    /// The work of delivering batches: until ``finish()``, it gathers the tracked records by the
    /// pipeline's strategy and delivers each batch to every destination at once, then waits for
    /// all of them before the next.
    ///
    /// Events tracked before it runs are held for it. Cancelling it stops delivery and drops the
    /// records still pending; call ``finish()`` to deliver them first.
    ///
    /// - Returns: A unit of work that completes once the last batch is delivered, and throws what
    ///   the strategy throws, or `CancellationError` when cancelled.
    /// - Precondition: A pipeline runs once: executing this work a second time, or the work of a
    ///   second call, traps.
    public func run() -> some AsynchronousUnitOfWork<Void> {
        DeferredTask { [self] in
            // A local: the call opens the existential from a value, not from the stored property.
            let strategy = strategy
            try await deliver(subscription.take(), by: strategy)
        }
    }
}

extension Pipeline {
    /// Delivers each batch `strategy` gathers from `records` to every destination.
    // Generic, so the existential strategy is opened once here and `batch(strategy:)` sees its
    // concrete type.
    fileprivate func deliver(
        _ records: Subscription.Records, by strategy: some BatchStrategy<EventRecord>
    ) async throws {
        for try await batch in records.batch(strategy: strategy) {
            await withDiscardingTaskGroup { group in
                for destination in destinations {
                    group.addTask { await destination.receive(batch) }
                }
            }
        }
    }
}

extension Duration {
    /// The duration in seconds, as Foundation counts time.
    fileprivate var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
