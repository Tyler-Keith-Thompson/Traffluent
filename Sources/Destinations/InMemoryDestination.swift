import DequeModule
public import Events
import Synchronization

/// A destination that keeps the newest records it receives, in memory, for the app to read.
///
/// Deliver to it beside the destinations that send events away, then read what arrived: an
/// in-app event inspector or debug drawer listing what was just tracked, a recent-activity view,
/// a SwiftUI preview fed sample events, or a test checking what its code tracked.
///
/// ```swift
/// let destination = try InMemoryDestination(capacity: 500)
/// let tracker = Tracker()
/// tracker.track(SignedUp(plan: "pro"))
/// await tracker.finish()
/// try await tracker.records.batch().deliver(to: destination).execute()
/// destination.events(of: SignedUp.self)  // [SignedUp(plan: "pro")]
/// ```
///
/// It keeps at most `capacity` records, across batches: once a batch takes it past that, the
/// oldest records are dropped until the newest `capacity` remain. A batch some of whose records
/// were dropped is kept with the newest of them, so ``batches`` always holds ``records``, in
/// order. ``unbounded()`` keeps everything, for a run whose length the caller controls.
///
/// Copies share what they keep: the copy the delivery holds and the one the app reads are the
/// same log. Reading is safe from any thread while batches arrive.
public struct InMemoryDestination: Destination {
    /// The most records a destination keeps unless it is given another bound: 1,000.
    public static let defaultCapacity = 1_000

    private let log: Log

    /// A destination that keeps the newest ``defaultCapacity`` records it receives.
    public init() {
        log = Log(capacity: InMemoryDestination.defaultCapacity)
    }

    /// A destination that keeps the newest `capacity` records it receives.
    ///
    /// - Parameter capacity: The most records kept, across batches; the oldest are dropped first.
    /// - Throws: ``InvalidCapacity`` when `capacity` is below 1.
    public init(capacity: Int) throws(InvalidCapacity) {
        guard capacity >= 1 else { throw InvalidCapacity() }
        log = Log(capacity: capacity)
    }

    private init(log: Log) {
        self.log = log
    }

    /// A destination that keeps every record it receives, and buffers every batch on
    /// ``deliveries`` until it is read.
    ///
    /// Its memory grows with every batch, so use it only where the caller ends the run: a test,
    /// a preview, a command-line tool.
    ///
    /// - Returns: An empty destination without a bound.
    public static func unbounded() -> InMemoryDestination {
        InMemoryDestination(log: Log(capacity: nil))
    }

    /// Keeps `batch`, dropping the oldest records past the capacity, then announces it on
    /// ``deliveries``.
    public func receive(_ batch: [EventRecord]) async {
        log.kept.withLock { $0.append(batch) }
        log.continuation.yield(batch)
    }

    /// The batches kept, in the order received.
    ///
    /// The oldest may hold only the newest of its records, when the capacity dropped the rest.
    /// An empty batch is announced on ``deliveries`` but not kept.
    ///
    /// - Complexity: O(*n*), where *n* is the number of records kept.
    public var batches: [[EventRecord]] {
        log.kept.withLock { $0.batches }
    }

    /// The records kept, in the order received, across batches.
    ///
    /// - Complexity: O(*n*), where *n* is the number of records kept.
    public var records: [EventRecord] {
        log.kept.withLock { Array($0.records) }
    }

    /// The events of type `type` kept, in the order received; records of other types are left
    /// out.
    ///
    /// - Parameter type: The event type to read.
    /// - Returns: Each kept event of that type, as that type.
    /// - Complexity: O(*n*), where *n* is the number of records kept.
    public func events<E: Event>(of type: E.Type) -> [E] {
        log.kept.withLock { $0.records.compactMap { $0.event as? E } }
    }

    /// Each batch as it is received, whole, for a reader that waits for a delivery: a view that
    /// refreshes, or a test that reads once a batch arrives.
    ///
    /// The stream has one consumer: iterate it from a single task, which can fan each batch out
    /// to the rest of the app. A second iterator takes batches from the first rather than seeing
    /// them too. Batches not yet read wait in a buffer of the newest `capacity` batches; a slower
    /// reader misses the older ones, and reads ``records`` for what is kept. The stream never
    /// finishes.
    public var deliveries: AsyncStream<[EventRecord]> {
        log.deliveries
    }
}

extension InMemoryDestination {
    /// The log every copy of a destination shares.
    private final class Log: Sendable {
        // A Mutex rather than an actor: an inspector's view or a test reads the log synchronously,
        // and each receive appends and evicts without awaiting, so the lock is held for moments.
        // Switch to an actor if receiving ever has to await while holding the log.
        let kept: Mutex<Kept>
        let deliveries: AsyncStream<[EventRecord]>
        let continuation: AsyncStream<[EventRecord]>.Continuation

        /// A log of at most `capacity` records, or of every record when `capacity` is `nil`.
        init(capacity: Int?) {
            kept = Mutex(Kept(capacity: capacity))
            let policy: AsyncStream<[EventRecord]>.Continuation.BufferingPolicy =
                if let capacity { .bufferingNewest(capacity) } else { .unbounded }
            (deliveries, continuation) = AsyncStream.makeStream(of: [EventRecord].self, bufferingPolicy: policy)
        }
    }

    /// The newest records received, with where each kept batch ends.
    private struct Kept: Sendable {
        let capacity: Int?
        // Deques rather than arrays: dropping the oldest records and batch sizes is O(1) each,
        // where Array.removeFirst shifts every record kept.
        var records: Deque<EventRecord> = []
        /// The number of records each kept batch still holds, oldest first.
        var batchSizes: Deque<Int> = []

        init(capacity: Int?) {
            self.capacity = capacity
        }

        /// Appends `batch`, unless it is empty, then drops the oldest records, and the batches
        /// left empty, past the capacity.
        mutating func append(_ batch: [EventRecord]) {
            guard !batch.isEmpty else { return }
            records.append(contentsOf: batch)
            batchSizes.append(batch.count)
            guard let capacity, records.count > capacity else { return }
            var excess = records.count - capacity
            records.removeFirst(excess)
            while excess > 0 {
                if batchSizes[0] <= excess {
                    excess -= batchSizes.removeFirst()
                } else {
                    batchSizes[0] -= excess
                    excess = 0
                }
            }
        }

        /// The kept records, split where each kept batch ends.
        var batches: [[EventRecord]] {
            var batches: [[EventRecord]] = []
            batches.reserveCapacity(batchSizes.count)
            var start = records.startIndex
            for size in batchSizes {
                batches.append(Array(records[start ..< start + size]))
                start += size
            }
            return batches
        }
    }
}
