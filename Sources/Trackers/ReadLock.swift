internal import Synchronization

/// Whose turn it is to read a tracker's records: one reader at a time, the others waiting in the
/// order they came.
///
/// A reader takes the turn with its first read and keeps it between reads, until its iteration
/// ends or its last copy is released. Then the first reader waiting takes it. So a reader never
/// reaches the subscription while another holds the turn, and the subscription, which traps when
/// two calls wait on it, sees one reader at a time.
final class ReadLock: Sendable {
    private struct Waiter {
        let id: UInt64
        let reader: ObjectIdentifier
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct State {
        /// The reader holding the turn. While any reader waits, one holds it: a release hands the
        /// turn straight to the first waiter.
        var owner: ObjectIdentifier?
        // An array rather than a deque: it holds one entry per reader reading at once, a handful
        // at most, so removing the first entry costs less than a dependency would.
        var waiters: [Waiter] = []
        var nextWaiterID: UInt64 = 0

        /// Gives `reader` the turn if it holds it already or no one does.
        mutating func grant(to reader: ObjectIdentifier) -> Bool {
            guard owner == nil || owner == reader else { return false }
            owner = reader
            return true
        }
    }

    // A Mutex, not an actor: a reader's deinit gives the turn back synchronously, which an actor
    // can't take without starting a task, and an actor would add a hop to every read. Not an
    // Atomic: the state includes a queue of continuations.
    private let state = Mutex(State())

    /// Gives `reader` the turn if no other reader holds it; `false`, changing nothing, otherwise.
    fileprivate func tryAcquire(_ reader: ObjectIdentifier) -> Bool {
        state.withLock { $0.grant(to: reader) }
    }

    /// Waits for `reader`'s turn, behind every reader already waiting: `true` once it has the
    /// turn, `false` if the waiting task is cancelled first.
    fileprivate func acquire(_ reader: ObjectIdentifier) async -> Bool {
        let id = state.withLock { state in
            defer { state.nextWaiterID += 1 }
            return state.nextWaiterID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let answer: Bool? = state.withLock { state in
                    if state.grant(to: reader) { return true }
                    // Checked under the lock, before the waiter is queued: a cancellation handler
                    // that ran before this found no waiter to resume, and the task's cancelled
                    // flag is set before its handlers run, so it is seen here.
                    if Task.isCancelled { return false }
                    state.waiters.append(Waiter(id: id, reader: reader, continuation: continuation))
                    return nil
                }
                if let answer { continuation.resume(returning: answer) }
            }
        } onCancel: {
            let waiter: Waiter? = state.withLock { state in
                guard let index = state.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return state.waiters.remove(at: index)
            }
            waiter?.continuation.resume(returning: false)
        }
    }

    /// Ends `reader`'s turn, handing it to the first reader waiting; does nothing unless `reader`
    /// holds it.
    fileprivate func release(_ reader: ObjectIdentifier) {
        let next: Waiter? = state.withLock { state in
            guard state.owner == reader else { return nil }
            guard !state.waiters.isEmpty else {
                state.owner = nil
                return nil
            }
            let next = state.waiters.removeFirst()
            state.owner = next.reader
            return next
        }
        next?.continuation.resume(returning: true)
    }

    /// One iterator's place in the lock, shared by the iterator's copies. Releasing its last copy
    /// ends its turn, so a reader whose task ends without finishing its iteration (a cancelled
    /// delivery) hands the turn on.
    final class Reader: Sendable {
        private let lock: ReadLock

        init(lock: ReadLock) {
            self.lock = lock
        }

        deinit {
            lock.release(ObjectIdentifier(self))
        }

        /// Takes the turn if no other reader holds it; `false` otherwise.
        func tryAcquire() -> Bool {
            lock.tryAcquire(ObjectIdentifier(self))
        }

        /// Waits for the turn: `true` once taken, `false` if the waiting task is cancelled first.
        func acquire() async -> Bool {
            await lock.acquire(ObjectIdentifier(self))
        }

        /// Ends the turn, if this reader holds it.
        func release() {
            lock.release(ObjectIdentifier(self))
        }
    }
}
