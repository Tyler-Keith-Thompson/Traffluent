extension AsyncQueue {
    /// The writing end of a queue an app makes: it adds elements and ends the queue, while
    /// ``queue`` is handed to the code that reads.
    ///
    /// ```swift
    /// let drops = AsyncQueue<String>.Continuation(name: "the app's drop reports")
    /// drops.enqueue("Not stored: notPersisted(event: \"Scrolled\")")
    /// let reads = drops.queue
    /// ```
    ///
    /// Copies of a continuation write to the same queue. The queue ends once ``finish()`` is
    /// called, or once the continuation and every copy of it are gone, and every element before
    /// the end has been read. It keeps every element no one has read yet, without a bound.
    public struct Continuation: Sendable {
        // A class every copy shares, so the last copy to go ends the queue, as AsyncStream's
        // continuation does.
        private let writer: Writer

        /// The queue this continuation writes to, for the code that reads it.
        public var queue: AsyncQueue<Element> {
            writer.queue
        }

        /// A continuation writing to a new, empty queue.
        ///
        /// - Parameter name: What the queue holds, for the warning a reader logs as it waits its
        ///   turn: "the app's drop reports".
        public init(name: String) {
            writer = Writer(queue: AsyncQueue(name: name))
        }

        /// Hands `element` to the read waiting for one, or keeps it for the next read; dropped
        /// once the queue is finished.
        ///
        /// It never waits, so any thread or task may call it.
        ///
        /// - Parameter element: The element to read after those already kept.
        public func enqueue(_ element: Element) {
            writer.queue.enqueue(element)
        }

        /// Ends the queue after the elements it keeps: reads return those, then `nil`. Elements
        /// enqueued after it are dropped.
        public func finish() {
            writer.queue.finish()
        }
    }
}

extension AsyncQueue.Continuation {
    /// The queue a continuation and its copies write to, ended once the last of them is gone.
    fileprivate final class Writer: Sendable {
        let queue: AsyncQueue<Element>

        init(queue: AsyncQueue<Element>) {
            self.queue = queue
        }

        deinit {
            queue.finish()
        }
    }
}
