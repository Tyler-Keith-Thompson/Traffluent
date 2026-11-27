internal import AsyncQueues
public import Events
import Logging

extension Tracker {
    /// The records of the events a tracker tracks, in the order tracked: what a delivery reads.
    ///
    /// ```swift
    /// let tracker = Tracker()
    /// let delivery = tracker.records
    ///     .batch(strategy: .count(20))
    ///     .deliver(to: ConsoleDestination())
    /// ```
    ///
    /// The sequence ends once the tracker's ``Tracker/finish()`` is called, or its every copy is
    /// released, and every record before it has been read. Records tracked while nothing is reading wait in memory, without a
    /// bound, for the next read, so none tracked before a delivery starts, or between two, is lost.
    /// A read whose task is cancelled returns `nil` and takes nothing: the next read gets the
    /// record it was waiting for, and every one after. A ``Tracker/noOp`` tracker's records are
    /// empty.
    ///
    /// One task reads at a time. The first iterator to read holds the records until its iteration
    /// ends or the iterator is released, as it is when its task ends. An iterator that reads
    /// meanwhile waits its turn, logging a warning as it starts to, then reads on from the next
    /// record; several wait in the order they came, and one whose task is cancelled while it
    /// waits returns `nil`. So a delivery started right after a cancelled one has stopped, or
    /// while it is stopping, delivers every record the cancelled one didn't read.
    public struct Records: AsyncSequence, Sendable {
        public typealias Element = EventRecord
        public typealias Failure = Never

        private static let logger = Logger(label: "Trackers.Records")

        let subscription: Subscription?

        /// Reads a tracker's records.
        public struct AsyncIterator: AsyncIteratorProtocol {
            public typealias Element = EventRecord
            public typealias Failure = Never

            let subscription: Subscription?
            private let reader: ReadLock.Reader?
            private var hasWarned = false

            init(subscription: Subscription?) {
                self.subscription = subscription
                reader = subscription.map { ReadLock.Reader(lock: $0.readLock) }
            }

            /// The next record tracked, or `nil` once the tracker is finished or the reading task
            /// is cancelled. Waits first while another iterator holds the records.
            public mutating func next() async -> EventRecord? {
                guard let subscription, let reader else { return nil }
                if !reader.tryAcquire() {
                    if !hasWarned {
                        hasWarned = true
                        // Once per iterator, not per call site: `next()` is the protocol's, so it
                        // has no source location to key on.
                        Records.logger.warning("Waiting to read a tracker's records: another reader holds them until its iteration ends or its iterator is released. One task reads a tracker's records at a time")
                    }
                    guard await reader.acquire() else { return nil }
                }
                guard let record = await subscription.next() else {
                    // The end, or a cancelled read: either way the turn passes to the next reader.
                    reader.release()
                    return nil
                }
                return record
            }
        }

        /// An iterator over the records; reading starts with its first `next()`.
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(subscription: subscription)
        }
    }
}
