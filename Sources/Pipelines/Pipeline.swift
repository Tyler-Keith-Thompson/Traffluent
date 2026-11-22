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
/// Tracking stamps the event with the wall-clock time and the caller's source location, and sends
/// the record through an Afluent `PassthroughSubject`. ``run()`` batches the records by the
/// pipeline's strategy and delivers each batch.
///
/// Records live in memory only. Events tracked while no run is reading wait in memory, without a
/// bound, until one does. Records not yet delivered, pending in a batch or waiting for a
/// destination, are lost if the process exits or the run is cancelled.
public struct Pipeline: Sendable {
    // Existentials: one pipeline holds destinations of different types, and a strategy whose type
    // the pipeline's own type doesn't carry, so every pipeline is a `Pipeline`.
    let destinations: [any Destination]
    private let strategy: any BatchStrategy<EventRecord>
    let batchBufferLimit: Int
    let subject = PassthroughSubject<EventRecord>()
    let subscription: Subscription
    let now: @Sendable () -> Date

    /// A pipeline delivering to `destinations`, every 20 events and every 30 seconds by `clock`
    /// while any are pending.
    ///
    /// - Parameters:
    ///   - destinations: Where each batch goes.
    ///   - clock: The clock the 30 seconds are measured on.
    ///   - now: The wall-clock time each event is stamped with when it is tracked.
    ///   - batchBufferLimit: How many batches each destination may have waiting while it is
    ///     still receiving an earlier one; when a new batch would pass it, the oldest waiting
    ///     batch is dropped.
    /// - Precondition: `batchBufferLimit` is at least 1.
    public init(
        _ destinations: any Destination...,
        // The core takes its dependencies as parameters rather than through a DI container's
        // registrations, so that adopters don't need the DI framework.
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now },
        batchBufferLimit: Int = 100
    ) {
        self.init(
            destinations,
            strategy: EitherBatchStrategy(.count(20), .time(interval: .seconds(30), clock: clock)),
            now: now,
            batchBufferLimit: batchBufferLimit)
    }

    /// A pipeline delivering to `destinations`, in batches `strategy` decides.
    ///
    /// Afluent's strategies compose: `.count(_:)`, `.time(interval:clock:tolerance:)`,
    /// `.signal(_:)` and `.either(_:_:)`.
    ///
    /// - Parameters:
    ///   - destinations: Where each batch goes.
    ///   - strategy: When the pending records are delivered as a batch.
    ///   - now: The wall-clock time each event is stamped with when it is tracked.
    ///   - batchBufferLimit: How many batches each destination may have waiting while it is
    ///     still receiving an earlier one; when a new batch would pass it, the oldest waiting
    ///     batch is dropped.
    /// - Precondition: `batchBufferLimit` is at least 1.
    public init(
        _ destinations: any Destination...,
        strategy: some BatchStrategy<EventRecord>,
        // The core takes its dependencies as parameters rather than through a DI container's
        // registrations, so that adopters don't need the DI framework.
        now: @escaping @Sendable () -> Date = { Date.now },
        batchBufferLimit: Int = 100
    ) {
        self.init(destinations, strategy: strategy, now: now, batchBufferLimit: batchBufferLimit)
    }

    private init(
        _ destinations: [any Destination],
        strategy: some BatchStrategy<EventRecord>,
        now: @escaping @Sendable () -> Date,
        batchBufferLimit: Int
    ) {
        precondition(batchBufferLimit >= 1, "A destination's batch buffer must hold at least 1 batch, not \(batchBufferLimit)")
        self.destinations = destinations
        self.strategy = strategy
        self.now = now
        self.batchBufferLimit = batchBufferLimit
        subscription = Subscription(to: subject)
    }

    /// Records `event`, with the current wall-clock time and the caller's source location, for
    /// the next batch.
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
        let timestamp = now()
        subject.send(EventRecord(event: event, timestamp: timestamp, sourceLocation: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column)))
    }

    /// Ends tracking: ``run()`` delivers the records still pending as a last batch, then finishes.
    public func finish() {
        subject.send(completion: .finished)
    }

    /// The work of delivering batches: until ``finish()``, it gathers the tracked records by the
    /// pipeline's strategy and hands each batch to every destination.
    ///
    /// Each destination receives its batches in order, one at a time, from a buffer of its own,
    /// so a slow destination delays only itself. Once ``finish()`` is called, the work completes
    /// after every destination has received its last batch.
    ///
    /// Events tracked while no run is reading are held for the next run. When a run ends,
    /// whether finished, cancelled or failed, the pipeline can run again, and executing the work
    /// again (a retry) runs again. Cancelling drops the records the run had pending and those
    /// tracked while it was stopping.
    ///
    /// - Returns: A unit of work that completes once the last batch is delivered, and throws what
    ///   the strategy throws, or `CancellationError` when cancelled.
    /// - Precondition: One run at a time: executing a run while another is in progress traps.
    public func run() -> some AsynchronousUnitOfWork<Void> {
        DeferredTask { [self] in
            let records = subscription.take()
            defer { subscription.release() }
            // A local: the call opens the existential from a value, not from the stored property.
            let strategy = strategy
            try await deliver(records, by: strategy)
        }
    }
}

extension Pipeline {
    /// Delivers each batch `strategy` gathers from `records` to every destination, through a
    /// buffer per destination.
    // Generic, so the existential strategy is opened once here and `batch(strategy:)` sees its
    // concrete type.
    fileprivate func deliver(
        _ records: Subscription.Records, by strategy: some BatchStrategy<EventRecord>
    ) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            // Dropping the oldest batch when a destination falls behind keeps memory bounded and
            // favours recent events, which the destination is likelier still to need; a slow or
            // stuck destination loses its backlog rather than holding up the others. The bound
            // is the caller's, 100 batches by default: at 20 events a batch, 2,000 events.
            let buffers = destinations.map { destination in
                let (batches, buffer) = AsyncStream.makeStream(
                    of: [EventRecord].self, bufferingPolicy: .bufferingNewest(batchBufferLimit))
                group.addTask {
                    for await batch in batches {
                        await destination.receive(batch)
                    }
                }
                return buffer
            }
            defer {
                for buffer in buffers { buffer.finish() }
            }
            for try await batch in records.batch(strategy: strategy) {
                for buffer in buffers { buffer.yield(batch) }
            }
        }
    }
}
