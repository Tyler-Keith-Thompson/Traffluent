internal import Afluent
internal import Events
internal import Synchronization

/// A pipeline's one subscription to its subject, made when the pipeline is.
///
/// A `PassthroughSubject` drops what is sent while no one is subscribed, and batching subscribes
/// only once its own task starts. Subscribing up front holds every event tracked before
/// `Pipeline.run()` gets going, so none is lost.
final class Subscription: Sendable {
    // A Mutex rather than an actor: it is taken once, synchronously, when the pipeline runs.
    private let iterator: Mutex<PassthroughSubject<EventRecord>.Iterator?>

    /// The subscription of a new subscriber to `subject`.
    init(to subject: PassthroughSubject<EventRecord>) {
        iterator = Mutex(subject.makeAsyncIterator())
    }

    /// The records sent to the subject since the subscription was made, as a sequence to iterate
    /// once.
    ///
    /// Traps when called a second time: one subscriber can't be read by two consumers, and a
    /// second run has no events left to deliver.
    func take() -> Records {
        let iterator = iterator.withLock { $0.take() }
        // A trap rather than an error: running a pipeline twice is a programming mistake no
        // caller could recover from, as the first run already consumed the subscription.
        guard let iterator else {
            preconditionFailure("A pipeline runs once")
        }
        return Records(iterator: iterator)
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
