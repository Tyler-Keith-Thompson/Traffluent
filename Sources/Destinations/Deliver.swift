public import Afluent
public import Events

extension AsyncSequence where Self: Sendable, Element == [EventRecord] {
    /// The work of delivering each batch of this sequence to every destination, until the
    /// sequence ends.
    ///
    /// ```swift
    /// let delivery = tracker.records
    ///     .batch(strategy: .count(20))
    ///     .deliver(to: ConsoleDestination(), vendor)
    /// try await delivery.execute()
    /// ```
    ///
    /// Each destination receives its batches in order, one at a time, from a buffer of its own,
    /// so a slow destination delays only itself. When a batch arrives while a destination's
    /// buffer already holds `batchBufferLimit` batches, the oldest waiting batch is dropped.
    /// Once the sequence ends, the work completes after every destination has received its last
    /// batch.
    ///
    /// Nothing runs until the work is executed, and each execution reads the sequence again, so
    /// a delivery that finished or failed can be executed again (a retry). Cancelling it drops
    /// the batches its destinations had waiting, and is permanent, as for every Afluent unit of
    /// work: executing a cancelled delivery again throws `CancellationError` at once, so build a
    /// new one instead.
    ///
    /// - Parameters:
    ///   - destinations: Where each batch goes.
    ///   - batchBufferLimit: How many batches each destination may have waiting while it is
    ///     still receiving an earlier one.
    /// - Returns: A unit of work that completes once the last batch is delivered, and throws what
    ///   the sequence throws, or `CancellationError` when cancelled.
    /// - Precondition: `batchBufferLimit` is at least 1.
    public func deliver(
        to destinations: any Destination...,
        batchBufferLimit: Int = 100
    ) -> some AsynchronousUnitOfWork<Void> {
        precondition(batchBufferLimit >= 1, "A destination's batch buffer must hold at least 1 batch, not \(batchBufferLimit)")
        return DeferredTask { [self] in
            try await withThrowingDiscardingTaskGroup { group in
                // Dropping the oldest batch when a destination falls behind keeps memory bounded
                // and favours recent events, which the destination is likelier still to need; a
                // slow or stuck destination loses its backlog rather than holding up the others.
                // The bound is the caller's, 100 batches by default: at 20 events a batch, 2,000
                // events. AsyncStream, rather than an Afluent subject or `share()`, because those
                // buffer each subscriber without a bound and have no drop-oldest policy.
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
                for try await batch in self {
                    for buffer in buffers { buffer.yield(batch) }
                }
            }
        }
    }
}
