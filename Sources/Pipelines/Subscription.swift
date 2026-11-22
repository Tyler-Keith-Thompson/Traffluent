internal import Afluent
internal import Events
internal import Synchronization

/// A pipeline's subscription to its subject, held between runs and handed to one run at a time.
///
/// A `PassthroughSubject` drops what is sent while no one is subscribed, and batching subscribes
/// only once its own task starts. Subscribing up front, when the pipeline is created and again
/// whenever a run ends, holds every event tracked while no run is reading, so none is lost.
/// Subscribing again is needed because a subscription whose read is cancelled removes itself
/// from the subject.
final class Subscription: Sendable {
    /// Whether a run is reading, and the subscription waiting for the next one when none is.
    private enum State: Sendable {
        case idle(PassthroughSubject<EventRecord>.Iterator)
        case running
    }

    private let subject: PassthroughSubject<EventRecord>
    // A Mutex rather than an actor: a run takes and returns it synchronously, once each.
    private let state: Mutex<State>

    /// A new subscriber to `subject`.
    init(to subject: PassthroughSubject<EventRecord>) {
        self.subject = subject
        state = Mutex(.idle(subject.makeAsyncIterator()))
    }

    /// The records sent to the subject since the subscription was made, for the run that calls
    /// it to read.
    ///
    /// Traps while another run is reading: one subscriber can't feed two consumers.
    func take() -> Records {
        let iterator: PassthroughSubject<EventRecord>.Iterator? = state.withLock { state in
            guard case .idle(let iterator) = state else { return nil }
            state = .running
            return iterator
        }
        // A trap rather than an error: two runs at once is a programming mistake no caller could
        // handle, as only one of them can read the events.
        guard let iterator else {
            preconditionFailure("A pipeline runs one run at a time")
        }
        return Records(iterator: iterator)
    }

    /// Ends the current run's reading: subscribes again, so the next run gets every event sent
    /// from now on.
    func release() {
        let iterator = subject.makeAsyncIterator()
        state.withLock { $0 = .idle(iterator) }
    }
}

extension Subscription {
    /// The records a subscription receives, in the order they were sent.
    struct Records: AsyncSequence, Sendable {
        let iterator: PassthroughSubject<EventRecord>.Iterator

        func makeAsyncIterator() -> PassthroughSubject<EventRecord>.Iterator {
            iterator
        }
    }
}
