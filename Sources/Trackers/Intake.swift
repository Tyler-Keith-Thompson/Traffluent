internal import Afluent
internal import Events
internal import Persistence

/// A tracker's intake and its worker: `track`, `grant` and `deny` only enqueue an entry; the
/// worker, the intake's one consumer, does everything else in the order the entries came.
///
/// The structure keeps a tracker's callers, the main thread included, clear of its work: the
/// intake is private, the worker is the only code that reads it, and nothing a caller can reach
/// runs enrichers, consent, encoding, a store's writes or a reader of ``Tracker/records``.
final class Intake: Sendable {
    /// What a caller hands the worker.
    enum Entry: Sendable {
        /// A record as `track` made it: its context as the caller's task held it, not yet
        /// enriched or gated.
        case track(EventRecord)
        /// A consent decision, in the order of the tracks around it.
        case decide(Set<ConsentCategory>, ConsentStatus)
        /// A wait for every entry before it, resumed with `true` once the worker reaches it.
        case flush(CheckedContinuation<Bool, Never>)
    }

    /// What the worker sends the records to, for ``Tracker/records`` to read.
    let subscription: Subscription
    // An AsyncStream rather than a Mutex-guarded Deque and a hand-written wait: its yield is
    // the O(1) append and wake-up the intake needs, safe from any thread, and it ends with
    // `finish()` after the entries already in it.
    private let entries: AsyncStream<Entry>.Continuation
    private let worker: Task<Void, Never>

    /// An intake whose worker delivers to `store`, if any, and gates by `consent`, if any.
    init(store: (any RecordStore)?, consent: Consent?, enrichers: [Enricher]) {
        let (stream, entries) = AsyncStream.makeStream(of: Entry.self)
        let subscription = Subscription()
        // Joined here, before `init` returns, so every decision made from now on reaches this
        // intake, in its order with the tracks.
        let membership = consent?.gate.join(entries)
        let worker = Worker(sink: RecordSink(subscription: subscription, store: store), store: store, enrichers: enrichers, membership: membership)
        self.subscription = subscription
        self.entries = entries
        // Detached, so the worker never runs on the actor that made the tracker, typically the
        // main actor, nor inherits the caller's task-locals: it reads only what entries carry.
        // On a utility dispatch queue (Afluent's QueueExecutor) rather than the cooperative pool:
        // a store's write and an enricher block their thread, and the pool has only one thread
        // per core for every task in the process.
        self.worker = Task.detached(executorPreference: .globalQueue(qos: .utility)) {
            await worker.run(stream)
        }
    }

    deinit {
        // Every tracker copy is gone, so nothing more can be tracked: the worker finishes what
        // is queued and ends the records, and the intake keeps nothing alive.
        entries.finish()
    }

    /// Queues `entry` for the worker; `false` once the intake is finished.
    func enqueue(_ entry: Entry) -> Bool {
        if case .terminated = entries.yield(entry) {
            return false
        }
        return true
    }

    /// Waits until the worker has handled every entry queued before the call.
    func flush() async {
        let queued = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            if !enqueue(.flush(continuation)) {
                continuation.resume(returning: false)
            }
        }
        if !queued {
            await worker.value
        }
    }

    /// Takes no more entries, then waits for the worker to handle those queued and end.
    func finish() async {
        entries.finish()
        await worker.value
    }
}
