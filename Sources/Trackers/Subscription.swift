internal import Afluent
internal import Events

/// A tracker's subject and its one subscription, which every reader of the tracker's records reads
/// in turn.
///
/// A `PassthroughSubject` drops what is sent while no one is subscribed, and a reader such as
/// `batch(strategy:)` subscribes only once its own task starts. Subscribing up front, when the
/// tracker is made, holds every event tracked before the first read.
///
/// The subscription is a `SubjectSubscription`, not the subject's iterator: a cancelled read of an
/// iterator ends its subscription and discards the records it holds, while a cancelled read of a
/// `SubjectSubscription` ends only that read. So no record is lost to a cancellation, and the
/// subscription never changes.
struct Subscription: Sendable {
    private let subject: PassthroughSubject<EventRecord>
    private let subscription: SubjectSubscription<EventRecord>

    /// A subject with its subscription made.
    init() {
        let subject = PassthroughSubject<EventRecord>()
        self.subject = subject
        subscription = subject.makeSubscription()
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
        // The subject only ever finishes, never fails, so the one error is a cancelled read's
        // CancellationError, which the records' contract spells as nil.
        try? await subscription.next()
    }
}
