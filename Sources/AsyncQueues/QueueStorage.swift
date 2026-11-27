internal import DequeModule
internal import Synchronization

/// What every copy of an ``AsyncQueue`` and its iterators share: the elements kept, the read
/// waiting for the next, and whose turn it is to read.
// Hand-written rather than an AsyncStream or an Afluent subject, as neither keeps the turn:
// - AsyncStream traps when a second task reads it while a read waits, and a read cancelled while
//   it waits finishes the stream for good, so no later reader gets another element.
// - Afluent's subjects drop what is sent while no one subscribes, have no buffering that merges
//   elements or keeps the newest n, and allow one subscription per task: from 1.1.49 a second
//   concurrent `next()` throws `ConcurrentNext` rather than wait.
final class QueueStorage<Element: Sendable>: Sendable {
    /// How a read ends.
    enum Outcome {
        /// The next element.
        case element(Element)
        /// The queue is finished and read, or the reading task was cancelled: the turn passes on.
        case end
        /// Another read was already waiting: a copy of the iterator holding the turn read from a
        /// second task. That read ends; the turn stays with the reader holding it.
        case concurrentRead
    }

    private struct Read {
        let id: UInt64
        let continuation: CheckedContinuation<Outcome, Never>
    }

    private struct State {
        // A Deque: a read takes the oldest element, which an Array would make O(n).
        var waiting: Deque<Element> = []
        /// The read waiting for the next element, if one is. Only the reader holding the turn
        /// reads, so there is at most one.
        var read: Read?
        var nextReadID: UInt64 = 0
        var isFinished = false
    }

    /// What the queue holds, for the warning a waiting reader logs.
    let name: String
    /// Whose turn it is to read.
    let readLock = ReadLock()
    private let buffering: AsyncQueue<Element>.Buffering
    // A Mutex rather than an actor: makers enqueue synchronously, from any thread, and a read's
    // cancellation handler, which can't await, takes it too.
    private let state = Mutex(State())

    init(name: String, buffering: AsyncQueue<Element>.Buffering) {
        self.name = name
        self.buffering = buffering
    }

    /// Hands `element` to the waiting read, or keeps it as the buffering says; dropped once
    /// finished.
    func enqueue(_ element: Element) {
        let read: Read? = state.withLock { state in
            guard !state.isFinished else { return nil }
            if let read = state.read {
                state.read = nil
                return read
            }
            buffering.add(element, &state.waiting)
            return nil
        }
        read?.continuation.resume(returning: .element(element))
    }

    /// Ends the queue after the elements kept.
    func finish() {
        let read: Read? = state.withLock { state in
            state.isFinished = true
            defer { state.read = nil }
            return state.read
        }
        read?.continuation.resume(returning: .end)
    }

    /// The next element, waiting for one; ``Outcome/end`` once finished and read, or when the
    /// reading task is cancelled, in which case the element stays for the next read.
    ///
    /// The caller holds the `readLock`'s turn, so no other read waits but one by a copy of the
    /// caller's iterator, which ends as ``Outcome/concurrentRead``.
    func next() async -> Outcome {
        let id = state.withLock { state in
            defer { state.nextReadID += 1 }
            return state.nextReadID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
                let ready: Outcome? = state.withLock { state in
                    // Checked under the lock the cancellation handler takes too: a cancellation
                    // either came first, or finds this read waiting.
                    guard !Task.isCancelled else { return .end }
                    if !state.waiting.isEmpty {
                        return .element(state.waiting.removeFirst())
                    }
                    guard !state.isFinished else { return .end }
                    // A second read while one waits can only be a copy of the holding iterator
                    // read from another task: it ends, rather than replace the first and leave
                    // it waiting for ever, and without ending the turn the first still holds.
                    guard state.read == nil else { return .concurrentRead }
                    state.read = Read(id: id, continuation: continuation)
                    return nil
                }
                if let ready {
                    continuation.resume(returning: ready)
                }
            }
        } onCancel: {
            let read: Read? = state.withLock { state in
                guard let read = state.read, read.id == id else { return nil }
                state.read = nil
                return read
            }
            read?.continuation.resume(returning: .end)
        }
    }
}
