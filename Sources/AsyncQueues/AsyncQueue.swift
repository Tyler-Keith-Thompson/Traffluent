internal import Logging

/// The reports or deliveries a library type makes, in the order it makes them, kept until they
/// are read; one reader at a time reads them.
///
/// ```swift
/// let reports = store.dropReports
/// Task {
///     for await report in reports {
///         logger.warning("Dropped: \(report)")
///     }
/// }
/// ```
///
/// Elements made while no one reads wait for the next read, as the type that makes them buffers
/// them: without a bound, merged into one another, or the newest only, as its documentation says.
/// The sequence ends once its maker finishes it and every element before the end has been read.
///
/// One task reads at a time. The first iterator to read holds the queue until its iteration ends
/// or the iterator is released, as it is when its task ends. An iterator that reads meanwhile
/// waits its turn, logging a warning as it starts to, then reads on from the next element; several
/// wait in the order they came. So the reader holding the queue gets every element, in order, and
/// no other reader takes one from it. A read whose task is cancelled returns `nil` and takes
/// nothing, ending that iterator's turn: the next read, by it or by the reader waiting next, gets
/// the element it was waiting for. A reader cancelled while it waits its turn returns `nil` too,
/// leaving the reader holding the queue undisturbed.
public struct AsyncQueue<Element: Sendable>: AsyncSequence, Sendable {
    public typealias Failure = Never

    let storage: QueueStorage<Element>

    /// An empty queue, which keeps each element no read is waiting for as `buffering` says.
    ///
    /// - Parameters:
    ///   - name: What the queue holds, for the warning a reader logs as it waits its turn: "a
    ///     store's drop reports".
    ///   - buffering: How the queue keeps elements no read is waiting for.
    package init(name: String, buffering: Buffering = .unbounded) {
        storage = QueueStorage(name: name, buffering: buffering)
    }

    /// A queue already finished: its readers get `nil` at once.
    ///
    /// - Parameter name: What the queue holds, for the warning a waiting reader logs.
    package static func finished(name: String) -> AsyncQueue {
        let queue = AsyncQueue(name: name)
        queue.finish()
        return queue
    }

    /// Hands `element` to the read waiting for one, or keeps it as the queue's buffering says;
    /// dropped once the queue is finished.
    package func enqueue(_ element: Element) {
        storage.enqueue(element)
    }

    /// Ends the queue after the elements it keeps: reads return those, then `nil`.
    package func finish() {
        storage.finish()
    }

    /// Reads a queue, in turn with its other readers.
    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Failure = Never

        private let storage: QueueStorage<Element>
        private let reader: ReadLock.Reader
        private var hasWarned = false

        init(storage: QueueStorage<Element>) {
            self.storage = storage
            reader = ReadLock.Reader(lock: storage.readLock)
        }

        /// The next element, or `nil` once the queue is finished and read, or the reading task is
        /// cancelled. Waits first while another iterator holds the queue.
        public mutating func next() async -> Element? {
            if !reader.tryAcquire() {
                if !hasWarned {
                    hasWarned = true
                    // Once per iterator, not per call site: `next()` is the protocol's, so it has
                    // no source location to key on.
                    logger.warning("Waiting to read \(storage.name): another reader holds them until its iteration ends or its iterator is released. One task reads \(storage.name) at a time")
                }
                guard await reader.acquire() else { return nil }
            }
            switch await storage.next() {
            case .element(let element):
                return element
            case .end:
                // The end, or a cancelled read: either way the turn passes to the next reader.
                reader.release()
                return nil
            case .concurrentRead:
                // A copy of this iterator read from another task while this one waits: the
                // turn is still this one's.
                return nil
            }
        }
    }

    /// An iterator over the queue; reading starts with its first `next()`.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(storage: storage)
    }
}

// At file scope because a generic type can't hold a static stored property; one logger for every
// specialization of AsyncQueue.
private let logger = Logger(label: "AsyncQueues.AsyncQueue")
