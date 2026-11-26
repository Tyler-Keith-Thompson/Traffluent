public import Afluent
public import Events
import Foundation
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
    /// buffer already holds `batchBufferLimit` batches, the oldest waiting batch is dropped,
    /// logged and reported on `bufferDropReporter` as a ``BufferDropReport``. Its records kept in
    /// memory only are lost. Those a store keeps are not: once that destination has received
    /// every batch waiting in its buffer, the delivery reads them back from the store and hands
    /// them to that destination alone, one dropped batch at a time, oldest first. Read back, a
    /// record is as it was dropped: its `EventRecord.id`, `EventRecord.isRedelivered`, sensitive
    /// values and context, which the delivery keeps meanwhile. The delivery keeps track of at
    /// most ten times `batchBufferLimit` dropped batches per destination; past that it forgets
    /// the oldest, whose records stay in the store for the next launch, and logs it. Once the
    /// sequence ends, the work completes after every destination has received its last batch,
    /// the ones read back included.
    ///
    /// Records a store keeps (those with an `EventRecord.deliveryTag`) are reported to it:
    /// before a batch goes to any destination, and again once every destination's `receive`
    /// has returned for it without being cancelled, when the store may forget them. A record
    /// the store couldn't mark as being delivered is left out of the batch, and a batch left
    /// with no records isn't sent. A record that some destination never received, because the
    /// store no longer kept it or couldn't read it back when the delivery asked, is never
    /// acknowledged, so a store that still keeps it delivers it on the next launch.
    ///
    /// Records the delivery has read but not delivered are lost to this run when it is cancelled
    /// or fails. Without a store they are gone; a store never had them acknowledged, so it
    /// delivers them on the next launch (unless its bound drops them first, which it reports).
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
    ///     still receiving an earlier one. A tenth of how many dropped batches it keeps track of
    ///     to read back.
    ///   - bufferDropReporter: Where a report of each batch a destination's full buffer drops is
    ///     yielded, as it is dropped; none by default. The delivery never finishes it, so one
    ///     reporter can serve the deliveries that replace one another.
    /// - Returns: A unit of work that completes once the last batch is delivered, and throws what
    ///   the sequence throws, or `CancellationError` when cancelled.
    /// - Throws: ``InvalidBatchBufferLimit`` when `batchBufferLimit` is below 1.
    public func deliver(
        to destinations: any Destination...,
        batchBufferLimit: Int,
        bufferDropReporter: AsyncStream<BufferDropReport>.Continuation? = nil
    ) throws(InvalidBatchBufferLimit) -> some AsynchronousUnitOfWork<Void> {
        guard batchBufferLimit >= 1 else { throw InvalidBatchBufferLimit() }
        return delivery(to: destinations, batchBufferLimit: batchBufferLimit, bufferDropReporter: bufferDropReporter)
    }

    /// The work of delivering each batch of this sequence to every destination, until the
    /// sequence ends, as `deliver(to:batchBufferLimit:bufferDropReporter:)` does, with a buffer of
    /// 100 batches for each destination.
    ///
    /// - Parameters:
    ///   - destinations: Where each batch goes.
    ///   - bufferDropReporter: Where a report of each batch a destination's full buffer drops is
    ///     yielded, as it is dropped; none by default.
    /// - Returns: A unit of work that completes once the last batch is delivered, and throws what
    ///   the sequence throws, or `CancellationError` when cancelled.
    public func deliver(
        to destinations: any Destination...,
        bufferDropReporter: AsyncStream<BufferDropReport>.Continuation? = nil
    ) -> some AsynchronousUnitOfWork<Void> {
        delivery(to: destinations, batchBufferLimit: 100, bufferDropReporter: bufferDropReporter)
    }

    /// The delivery to `destinations`, each with a buffer of `batchBufferLimit` batches, at least
    /// 1.
    private func delivery(
        to destinations: [any Destination],
        batchBufferLimit: Int,
        bufferDropReporter: AsyncStream<BufferDropReport>.Continuation?
    ) -> some AsynchronousUnitOfWork<Void> {
        DeferredTask { [self] in
            try await withThrowingDiscardingTaskGroup { group in
                // The bound is the caller's, 100 batches by default: at 20 events a batch, 2,000
                // events. DestinationBuffer says why the oldest is the one dropped.
                let buffers = destinations.enumerated().map { index, destination in
                    DestinationBuffer(destination: destination, index: index, limit: batchBufferLimit, reporter: bufferDropReporter)
                }
                for buffer in buffers {
                    group.addTask { await buffer.run() }
                }
                defer {
                    for buffer in buffers { buffer.finish() }
                }
                for try await batch in self {
                    // A batching sequence ends a cancelled delivery by handing over what was
                    // pending. Telling the store it is being delivered would mark records no
                    // destination will get as redelivered on the next launch.
                    if Task.isCancelled { break }
                    guard let delivery = Delivery(of: batch, destinationCount: buffers.count) else { continue }
                    for buffer in buffers { buffer.yield(delivery) }
                }
            }
        }
    }
}

/// A batch on its way to one destination, with the acknowledgement it counts towards.
struct Delivery: Sendable {
    let batch: [EventRecord]
    /// The earliest and the latest of the batch's timestamps.
    let timestamps: ClosedRange<Date>
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
        let times = delivered.map(\.timestamp)
        guard let earliest = times.min(), let latest = times.max() else { return nil }
        self.batch = delivered
        timestamps = earliest...latest
        acknowledgement = BatchAcknowledgement(of: delivered, destinationCount: destinationCount)
        if destinationCount == 0 {
            acknowledgement?.acknowledge()
        }
    }
}

/// One batch's acknowledgement to the stores that keep its records: sent once every destination
/// has received the batch, for the records every destination received.
final class BatchAcknowledgement: Sendable {
    /// The positions of a batch's records in one store.
    struct Positions: Sendable {
        let acknowledger: any Acknowledger
        var positions: [UInt64]
    }

    private struct State {
        /// How many destinations have yet to receive the batch.
        var remaining: Int
        /// The positions to acknowledge, by store: the batch's, less those a destination that
        /// had them read back didn't receive.
        var stores: [Positions]
    }

    // A Mutex rather than an actor: each destination's task counts down once, synchronously, as
    // its receive returns, and nothing waits while holding it.
    private let state: Mutex<State>

    /// The acknowledgement of `batch` from `destinationCount` destinations, or `nil` when no
    /// store keeps any of its records.
    init?(of batch: [EventRecord], destinationCount: Int) {
        let stores = Self.positionsByStore(in: batch)
        guard !stores.isEmpty else { return nil }
        state = Mutex(State(remaining: destinationCount, stores: stores))
    }

    /// The positions of `batch`'s records, grouped by the store that keeps them, in batch order.
    static func positionsByStore(in batch: [EventRecord]) -> [Positions] {
        positionsByStore(of: batch.compactMap(\.deliveryTag))
    }

    /// The positions `tags` name, grouped by store, in the order of `tags`.
    static func positionsByStore(of tags: [DeliveryTag]) -> [Positions] {
        var stores: [Positions] = []
        for tag in tags {
            if let index = stores.firstIndex(where: { $0.acknowledger === tag.acknowledger }) {
                stores[index].positions.append(tag.position)
            } else {
                stores.append(Positions(acknowledger: tag.acknowledger, positions: [tag.position]))
            }
        }
        return stores
    }

    /// Counts one destination's receipt of the whole batch, acknowledging it after the last.
    func received() {
        let finished: [Positions]? = state.withLock { state in
            state.remaining -= 1
            return state.remaining == 0 ? state.stores : nil
        }
        if let finished {
            Self.acknowledge(finished)
        }
    }

    /// Counts the receipt of a destination that received only the records at `kept`, by the
    /// identity of their store, out of those read back for it; the others are never acknowledged.
    func received(keeping kept: [ObjectIdentifier: Set<UInt64>]) {
        let finished: [Positions]? = state.withLock { state in
            for index in state.stores.indices {
                let keptInStore = kept[ObjectIdentifier(state.stores[index].acknowledger)] ?? []
                state.stores[index].positions.removeAll { !keptInStore.contains($0) }
            }
            state.remaining -= 1
            return state.remaining == 0 ? state.stores : nil
        }
        if let finished {
            Self.acknowledge(finished)
        }
    }

    /// Tells each store every destination has received its records.
    func acknowledge() {
        Self.acknowledge(state.withLock { $0.stores })
    }

    /// Tells each of `stores` every destination has received the records at its positions.
    private static func acknowledge(_ stores: [Positions]) {
        for store in stores where !store.positions.isEmpty {
            store.acknowledger.acknowledge(store.positions)
        }
    }
}
