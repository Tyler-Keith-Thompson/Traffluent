internal import Afluent
internal import Events
internal import Synchronization

/// A tracker's subject and its one subscription, which every reader of the tracker's records reads
/// in turn.
///
/// A `PassthroughSubject` drops what is sent while no one is subscribed, and a reader such as
/// `batch(strategy:)` subscribes only once its own task starts. Subscribing up front, when the
/// tracker is made, holds every event tracked before the first read.
///
/// A read of the subject that is cancelled removes the subscription, and with it the records it
/// holds. So no reader's task reads the subject: each read runs in a task of the subscription's
/// own, which nothing cancels, and readers wait for its result. A reader that is cancelled stops
/// waiting and leaves the read running; the next reader takes it over, or takes its result if it
/// finished meanwhile. No record is lost to a cancellation, and the subscription never changes.
final class Subscription: Sendable {
    /// A reader waiting for the read in flight.
    fileprivate struct Waiter: Sendable {
        /// Which `next()` call it is, so a late cancellation can't stop another reader's wait.
        let id: Int
        let continuation: CheckedContinuation<EventRecord?, Never>
    }

    /// Where the subscription is: between reads, being read, or holding a result no one took.
    fileprivate enum State: Sendable {
        /// No read is in flight.
        case idle(PassthroughSubject<EventRecord>.Iterator)
        /// The read task holds the subscription; `waiter` waits for its result, if anyone does.
        case reading(waiter: Waiter?)
        /// A read finished with no reader waiting: its result goes to the next reader.
        case read(EventRecord?, PassthroughSubject<EventRecord>.Iterator)
    }

    private struct Reads: Sendable {
        var state: State
        /// The task reading the subject, cancelled when the subscription goes away.
        var task: Task<Void, Never>?
        /// How many `next()` calls have started, which numbers the waiters.
        var calls = 0
    }

    private let subject = PassthroughSubject<EventRecord>()
    // A Mutex rather than an actor: a reader's wait, a cancellation handler (which can't await)
    // and the read task each take it synchronously and briefly.
    private let reads: Mutex<Reads>

    /// A subject with its subscription made.
    init() {
        reads = Mutex(Reads(state: .idle(subject.makeAsyncIterator())))
    }

    deinit {
        // The read task holds the subscription only weakly, so without this it would wait on
        // the subject for ever once the tracker is gone.
        reads.withLock { $0.task }?.cancel()
    }

    /// Sends `record` to the subscription; dropped once ``finish()`` was called.
    func send(_ record: EventRecord) {
        subject.send(record)
    }

    /// Ends the records: reads return what is pending, then `nil`.
    func finish() {
        subject.send(completion: .finished)
    }

    /// The next record sent, or `nil` once the subject is finished or the reading task is
    /// cancelled, in which case the record stays for the next reader.
    ///
    /// Traps while another reader is waiting: one subscription can't feed two readers.
    func next() async -> EventRecord? {
        let call = reads.withLock { reads in
            reads.calls += 1
            return reads.calls
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                wait(Waiter(id: call, continuation: continuation))
            }
        } onCancel: {
            stopWaiting(call)
        }
    }
}

extension Subscription {
    /// Makes `waiter` wait for the next record: from a read already finished, the one in flight,
    /// or a new one.
    fileprivate func wait(_ waiter: Waiter) {
        let ready: EventRecord?? = reads.withLock { reads in
            // Checked under the lock that stopWaiting takes too: a cancellation either came
            // first, and its handler found no waiter, or comes after and finds this one.
            guard !Task.isCancelled else { return .some(nil) }
            switch reads.state {
            case .idle(let iterator):
                reads.state = .reading(waiter: waiter)
                reads.task = read(iterator)
                return nil
            case .reading(waiter: nil):
                reads.state = .reading(waiter: waiter)
                return nil
            case .reading(waiter: .some):
                // A trap rather than an error: two readers at once is a programming mistake no
                // caller could handle, as only one of them can have each record.
                preconditionFailure("A tracker's records are read by one task at a time")
            case .read(let record, let iterator):
                reads.state = .idle(iterator)
                return .some(record)
            }
        }
        if let ready {
            waiter.continuation.resume(returning: ready)
        }
    }

    /// Ends the wait of `next()` call `call` with `nil`, leaving the read in flight for the next
    /// reader; does nothing if that call isn't waiting.
    fileprivate func stopWaiting(_ call: Int) {
        let stopped: Waiter? = reads.withLock { reads in
            guard case .reading(let waiter?) = reads.state, waiter.id == call else { return nil }
            reads.state = .reading(waiter: nil)
            return waiter
        }
        stopped?.continuation.resume(returning: nil)
    }

    /// Reads one record from the subject, in a task nothing but `deinit` cancels.
    fileprivate func read(_ iterator: PassthroughSubject<EventRecord>.Iterator) -> Task<Void, Never> {
        Task { [weak self] in
            var reading = iterator
            // The subject never fails: a tracker only finishes it.
            let record = (try? await reading.next()) ?? nil
            self?.finishRead(record, iterator: reading)
        }
    }

    /// Hands `record` to the reader waiting, or keeps it for the next one.
    fileprivate func finishRead(_ record: EventRecord?, iterator: PassthroughSubject<EventRecord>.Iterator) {
        let waiter: Waiter? = reads.withLock { reads in
            guard case .reading(let waiter) = reads.state else { return nil }
            reads.task = nil
            if waiter == nil {
                reads.state = .read(record, iterator)
            } else {
                reads.state = .idle(iterator)
            }
            return waiter
        }
        waiter?.continuation.resume(returning: record)
    }
}
