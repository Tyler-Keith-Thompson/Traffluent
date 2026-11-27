package import DequeModule

extension AsyncQueue {
    /// How a queue keeps an element no read is waiting for: added to the elements waiting,
    /// oldest first, or merged into one of them.
    package struct Buffering: Sendable {
        let add: @Sendable (Element, inout Deque<Element>) -> Void

        /// A buffering that keeps each element as `add` puts it into the elements waiting.
        ///
        /// - Parameter add: Adds an element to the elements waiting unread, oldest first:
        ///   appended, merged into one of them, or with older ones dropped. It runs under the
        ///   queue's lock, so it must not block.
        package init(adding add: @escaping @Sendable (_ element: Element, _ waiting: inout Deque<Element>) -> Void) {
            self.add = add
        }

        /// Every element, without a bound.
        package static var unbounded: Buffering {
            Buffering { element, waiting in waiting.append(element) }
        }

        /// The newest `limit` elements: an element past it drops the oldest waiting. A `limit`
        /// below 1 keeps none.
        package static func newest(_ limit: Int) -> Buffering {
            Buffering { element, waiting in
                waiting.append(element)
                let excess = waiting.count - Swift.max(limit, 0)
                if excess > 0 {
                    waiting.removeFirst(excess)
                }
            }
        }
    }
}
