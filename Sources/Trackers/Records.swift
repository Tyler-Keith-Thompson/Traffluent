public import Events

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
    /// The sequence ends once the tracker's ``Tracker/finish()`` is called and every record before
    /// it has been read. Records tracked while nothing is reading wait in memory, without a
    /// bound, for the next read, so none tracked before a delivery starts, or between two, is lost.
    /// A read whose task is cancelled returns `nil` and takes nothing: the next read gets the
    /// record it was waiting for, and every one after. A ``Tracker/noOp`` tracker's records are
    /// empty.
    ///
    /// One task reads at a time, as with `AsyncStream`: calling `next()` while another task's
    /// call is waiting traps. A reader that has been cancelled stops waiting as its cancellation
    /// reaches it, so start a new delivery once the cancelled one's `execute()` has returned.
    public struct Records: AsyncSequence, Sendable {
        public typealias Element = EventRecord
        public typealias Failure = Never

        let backing: Backing

        /// Reads a tracker's records.
        public struct AsyncIterator: AsyncIteratorProtocol {
            public typealias Element = EventRecord
            public typealias Failure = Never

            let backing: Backing

            /// The next record tracked, or `nil` once the tracker is finished or the reading task
            /// is cancelled.
            ///
            /// - Precondition: No other task's `next()` is waiting.
            public mutating func next() async -> EventRecord? {
                switch backing {
                case .subscription(let subscription):
                    await subscription.next()
                case .none:
                    nil
                }
            }
        }

        /// An iterator over the records; reading starts with its first `next()`.
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(backing: backing)
        }
    }
}
