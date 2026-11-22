public import Destinations
public import Events
import Synchronization

/// A destination that keeps every batch it receives, for tests.
///
/// Give it to a pipeline, run the pipeline, then read what arrived:
///
/// ```swift
/// let destination = InMemoryDestination()
/// let pipeline = Pipeline(destination)
/// pipeline.track(SignedUp(plan: "pro"))
/// pipeline.finish()
/// try await pipeline.run().execute()
/// destination.events(of: SignedUp.self)  // [SignedUp(plan: "pro")]
/// ```
///
/// Copies share what they record: the copy the pipeline holds and the one the test reads are the
/// same log. Reading is safe while batches arrive.
public struct InMemoryDestination: Destination {
    // A Mutex rather than an actor: tests read the log synchronously right after a run, and each
    // receive only appends, so the lock is held for moments. Switch to an actor if receiving ever
    // has to await while holding the log.
    private final class Log: Sendable {
        let batches = Mutex<[[EventRecord]]>([])
        let (deliveries, continuation) = AsyncStream.makeStream(of: [EventRecord].self)
    }

    private let log = Log()

    /// An empty destination.
    public init() {}

    /// Keeps `batch`, then announces it on ``deliveries``.
    public func receive(_ batch: [EventRecord]) async {
        log.batches.withLock { $0.append(batch) }
        log.continuation.yield(batch)
    }

    /// Every batch received, in the order received.
    public var batches: [[EventRecord]] {
        log.batches.withLock { $0 }
    }

    /// Every record received, in the order received, across batches.
    public var records: [EventRecord] {
        log.batches.withLock { $0.flatMap { $0 } }
    }

    /// The events of type `type` received, in the order received; records of other types are
    /// left out.
    ///
    /// - Parameter type: The event type to read.
    /// - Returns: Each received event of that type, as that type.
    public func events<E: Event>(of type: E.Type) -> [E] {
        log.batches.withLock { $0.flatMap { $0.compactMap { $0.event as? E } } }
    }

    /// Each batch as it is received, for a test that waits for a delivery before reading.
    ///
    /// The stream has one consumer: iterate it from a single task.
    public var deliveries: AsyncStream<[EventRecord]> {
        log.deliveries
    }
}
