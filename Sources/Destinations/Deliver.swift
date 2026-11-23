public import Afluent
public import Events
import Synchronization

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
    /// Records a store keeps (those with an `EventRecord.deliveryTag`) are reported to it:
    /// before a batch goes to any destination, and again once every destination's `receive`
    /// has returned for it without being cancelled, when the store may forget them. A record
    /// the store couldn't mark as being delivered is left out of the batch, and a batch left
    /// with no records isn't sent.
    ///
    /// Records the delivery has read but not delivered are lost to this run when it is cancelled
    /// or fails, and so are batches a destination's full buffer dropped. Without a store they are
    /// gone; a store never had them acknowledged, so it delivers them on the next launch (unless
    /// its bound drops them first, which it reports).
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
                    let (deliveries, buffer) = AsyncStream.makeStream(
                        of: Delivery.self, bufferingPolicy: .bufferingNewest(batchBufferLimit))
                    group.addTask {
                        for await delivery in deliveries {
                            await destination.receive(delivery.batch)
                            // A receive that returned because the delivery was cancelled may not
                            // have delivered the batch, so its store keeps the records.
                            guard !Task.isCancelled else { return }
                            delivery.acknowledgement?.received()
                        }
                    }
                    return buffer
                }
                defer {
                    for buffer in buffers { buffer.finish() }
                }
                for try await batch in self {
                    guard let delivery = Delivery(of: batch, destinationCount: buffers.count) else { continue }
                    for buffer in buffers { buffer.yield(delivery) }
                }
            }
        }
    }
}

/// A batch on its way to one destination, with the acknowledgement it counts towards.
private struct Delivery: Sendable {
    let batch: [EventRecord]
    let acknowledgement: BatchAcknowledgement?

    /// `batch` on its way to `destinationCount` destinations, its stores told, without the
    /// records they hold back; `nil` when none is left.
    init?(of batch: [EventRecord], destinationCount: Int) {
        var withheld: [ObjectIdentifier: Set<UInt64>] = [:]
        for store in BatchAcknowledgement.positionsByStore(in: batch) {
            let held = store.acknowledger.willDeliver(store.positions)
            if !held.isEmpty {
                withheld[ObjectIdentifier(store.acknowledger)] = held
            }
        }
        let delivered = withheld.isEmpty ? batch : batch.filter { record in
            guard let tag = record.deliveryTag, let held = withheld[ObjectIdentifier(tag.acknowledger)] else { return true }
            return !held.contains(tag.position)
        }
        guard !delivered.isEmpty else { return nil }
        self.batch = delivered
        acknowledgement = BatchAcknowledgement(of: delivered, destinationCount: destinationCount)
        if destinationCount == 0 {
            acknowledgement?.acknowledge()
        }
    }
}

/// One batch's acknowledgement to the stores that keep its records: sent once every destination
/// has received the batch.
private final class BatchAcknowledgement: Sendable {
    /// The positions of a batch's records in one store.
    struct Positions: Sendable {
        let acknowledger: any Acknowledger
        var positions: [UInt64]
    }

    private let stores: [Positions]
    // A Mutex rather than an actor: each destination's task counts down once, synchronously, as
    // its receive returns, and nothing waits while holding it.
    private let remaining: Mutex<Int>

    /// The acknowledgement of `batch` from `destinationCount` destinations, or `nil` when no
    /// store keeps any of its records.
    init?(of batch: [EventRecord], destinationCount: Int) {
        let stores = Self.positionsByStore(in: batch)
        guard !stores.isEmpty else { return nil }
        self.stores = stores
        remaining = Mutex(destinationCount)
    }

    /// The positions of `batch`'s records, grouped by the store that keeps them, in batch order.
    static func positionsByStore(in batch: [EventRecord]) -> [Positions] {
        var stores: [Positions] = []
        for record in batch {
            guard let tag = record.deliveryTag else { continue }
            if let index = stores.firstIndex(where: { $0.acknowledger === tag.acknowledger }) {
                stores[index].positions.append(tag.position)
            } else {
                stores.append(Positions(acknowledger: tag.acknowledger, positions: [tag.position]))
            }
        }
        return stores
    }

    /// Counts one destination's receipt, acknowledging the batch after the last.
    func received() {
        let isLast = remaining.withLock { remaining in
            remaining -= 1
            return remaining == 0
        }
        if isLast {
            acknowledge()
        }
    }

    /// Tells each store every destination has received its records.
    func acknowledge() {
        for store in stores {
            store.acknowledger.acknowledge(store.positions)
        }
    }
}
