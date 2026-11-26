import DequeModule
import Events
import Foundation
import Instrumentation
import Logging
import Synchronization

/// One destination's side of a delivery: the batches waiting while it receives an earlier one,
/// and the batches its full buffer dropped whose records a store keeps, to hand it again once it
/// has caught up.
final class DestinationBuffer: Sendable {
    private struct State {
        /// Deliveries yielded to the stream and not yet taken from it. Counted in the same lock
        /// as the yield and any drop it makes, so at 0 the stream is empty: the destination has
        /// caught up.
        var waitingCount = 0
        /// The batches the stream dropped that a store keeps records of, oldest first; at most
        /// `droppedLimit`.
        var dropped: Deque<DroppedBatch> = []
    }

    /// What a yield dropped: the batch, for its report, and any dropped batch the bound on
    /// `State.dropped` discarded to make room.
    private struct Drop {
        let batch: Delivery
        let discarded: DroppedBatch?
    }

    private let destination: any Destination
    private let index: Int
    private let limit: Int
    /// How many dropped batches are kept to read back: ten buffers' worth. Past it the oldest is
    /// discarded, left in its store for a later launch, so a destination that never catches up
    /// doesn't grow this without a bound.
    private let droppedLimit: Int
    private let deliveries: AsyncStream<Delivery>
    private let buffer: AsyncStream<Delivery>.Continuation
    private let reporter: AsyncStream<BufferDropReport>.Continuation?
    // A Mutex rather than an actor: the delivery's loop and the destination's task each take it
    // briefly, synchronously, once per batch, and nothing waits while holding it. The yield runs
    // inside it, which is safe as AsyncStream's yield never suspends or calls back.
    private let state = Mutex(State())

    private static let logger = Logger(label: "Destinations.DestinationBuffer")

    /// The buffer of `destination`, at `index` among the delivery's destinations, holding up to
    /// `limit` waiting batches and reporting each it drops to `reporter`.
    init(destination: any Destination, index: Int, limit: Int, reporter: AsyncStream<BufferDropReport>.Continuation?) {
        self.destination = destination
        self.index = index
        self.limit = limit
        droppedLimit = limit <= Int.max / 10 ? limit * 10 : Int.max
        self.reporter = reporter
        // Dropping the oldest batch when a destination falls behind keeps memory bounded and
        // favours recent events, which the destination is likelier still to need; a slow or stuck
        // destination loses its backlog rather than holding up the others, and a store's records
        // in it are read back later rather than held here. AsyncStream, rather than an Afluent
        // subject or `share()`, because those buffer each subscriber without a bound and have no
        // drop-oldest policy.
        (deliveries, buffer) = AsyncStream.makeStream(of: Delivery.self, bufferingPolicy: .bufferingNewest(limit))
    }

    /// Adds `delivery` to the waiting batches, dropping the oldest when `limit` are waiting.
    func yield(_ delivery: Delivery) {
        let drop: Drop? = state.withLock { state in
            state.waitingCount += 1
            guard case .dropped(let oldest) = buffer.yield(delivery) else { return nil }
            state.waitingCount -= 1
            guard let dropped = DroppedBatch(oldest) else { return Drop(batch: oldest, discarded: nil) }
            state.dropped.append(dropped)
            let discarded = state.dropped.count > droppedLimit ? state.dropped.removeFirst() : nil
            return Drop(batch: oldest, discarded: discarded)
        }
        guard let drop else { return }
        report(drop.batch)
        if let discarded = drop.discarded {
            Self.logger.notice("Destination \(index) has more than \(droppedLimit) dropped batches waiting to be read back, so the oldest one's \(discarded.records.count) stored records are left in the store for a later launch")
        }
    }

    /// Ends the waiting batches: ``run()`` returns once the destination has received them.
    func finish() {
        buffer.finish()
    }

    /// Hands the destination each waiting batch in turn, and the dropped ones whenever it has
    /// caught up, until ``finish()`` and the last of them, or until cancelled.
    func run() async {
        for await delivery in deliveries {
            state.withLock { $0.waitingCount -= 1 }
            await destination.receive(delivery.batch)
            // A receive that returned because the delivery was cancelled may not have delivered
            // the batch, so its store keeps the records.
            guard !Task.isCancelled else { return }
            delivery.acknowledgement?.received()
            guard await redeliverWhileCaughtUp() else { return }
        }
        // The stream ended. Every drop was counted with its yield, so the loop has already read
        // them back; this only makes sure, as nothing else would.
        guard !Task.isCancelled else { return }
        _ = await redeliverWhileCaughtUp()
    }

    /// Reads back and hands the destination each dropped batch, one at a time, for as long as it
    /// has caught up; `false` when the delivery was cancelled.
    private func redeliverWhileCaughtUp() async -> Bool {
        while let dropped = droppedOnceCaughtUp() {
            // Cancelled, the batch taken is left unacknowledged, in its store.
            guard !Task.isCancelled else { return false }
            let read = dropped.readBack()
            if !read.records.isEmpty {
                await destination.receive(read.records)
                guard !Task.isCancelled else { return false }
            }
            dropped.acknowledgement.received(keeping: read.kept)
        }
        return true
    }

    /// The oldest dropped batch, taken out of the state, when the destination has caught up and
    /// there is one; `nil` otherwise.
    private func droppedOnceCaughtUp() -> DroppedBatch? {
        state.withLock { state in
            guard state.waitingCount == 0 else { return nil }
            return state.dropped.popFirst()
        }
    }

    /// Reports and logs the buffer's drop of `dropped`.
    private func report(_ dropped: Delivery) {
        let stored = dropped.batch.count { $0.deliveryTag != nil }
        let report = BufferDropReport(
            destinationIndex: index,
            recordCount: dropped.batch.count,
            timestamps: dropped.timestamps,
            storedRecordCount: stored
        )
        let lost = dropped.batch.count - stored
        if lost == 0 {
            Self.logger.notice("Destination \(index)'s full buffer dropped a batch of \(stored) stored records, to be read back from the store once it catches up")
        } else {
            let readBack = stored == 0 ? "" : "; the other \(stored), stored, are read back once it catches up"
            Self.logger.error("Destination \(index)'s full buffer dropped a batch, losing \(lost) of its \(dropped.batch.count) records, kept in memory only\(readBack)")
        }
        reporter?.yield(report)
    }
}

/// A batch a destination's full buffer dropped, as kept to hand that destination again: where a
/// store keeps each of its stored records, and what the delivery must restore of each.
struct DroppedBatch: Sendable {
    /// A record of the batch a store keeps, less what the store keeps of it.
    struct StoredRecord: Sendable {
        let tag: DeliveryTag
        let isRedelivered: Bool
        let revealsSensitiveValues: Bool
        // Kept here, as no store keeps a record's context; small beside the event, which is
        // read back.
        let context: ServiceContext
    }

    /// One dropped batch's records as read back.
    struct ReadBatch {
        /// The records its stores returned, in batch order, as they were when the buffer dropped
        /// them.
        var records: [EventRecord] = []
        /// Their positions, by the identity of the store keeping them.
        var kept: [ObjectIdentifier: Set<UInt64>] = [:]
    }

    /// The batch's stored records, in batch order.
    let records: [StoredRecord]
    /// The acknowledgement the batch counts towards.
    let acknowledgement: BatchAcknowledgement

    /// `delivery`, dropped, or `nil` when no store keeps any of its records.
    init?(_ delivery: Delivery) {
        guard let acknowledgement = delivery.acknowledgement else { return nil }
        records = delivery.batch.compactMap { record in
            record.deliveryTag.map { tag in
                StoredRecord(tag: tag, isRedelivered: record.isRedelivered, revealsSensitiveValues: record.revealsSensitiveValues, context: record.context)
            }
        }
        self.acknowledgement = acknowledgement
    }

    /// The batch's records its stores still keep, read back with one read per store.
    func readBack() -> ReadBatch {
        var returned: [ObjectIdentifier: [UInt64: EventRecord]] = [:]
        for store in BatchAcknowledgement.positionsByStore(of: records.map(\.tag)) {
            let tagged = store.acknowledger.records(at: store.positions).compactMap { record in
                // Only the store asked, so a record tagged with another's can't stand in for one.
                record.deliveryTag.flatMap { $0.acknowledger === store.acknowledger ? ($0.position, record) : nil }
            }
            returned[ObjectIdentifier(store.acknowledger)] = Dictionary(tagged) { first, _ in first }
        }
        var read = ReadBatch()
        for stored in records {
            let store = ObjectIdentifier(stored.tag.acknowledger)
            guard var record = returned[store]?[stored.tag.position] else { continue }
            record.isRedelivered = stored.isRedelivered
            record.revealsSensitiveValues = stored.revealsSensitiveValues
            record.context = stored.context
            read.records.append(record)
            read.kept[store, default: []].insert(stored.tag.position)
        }
        return read
    }
}
