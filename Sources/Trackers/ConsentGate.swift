internal import AsyncQueues
internal import DequeModule
internal import Events
internal import Synchronization

/// What a ``Consent`` shares between its copies and the trackers given it: each category's
/// status, the intakes decisions go to, the records held while undecided, and the drop reports.
///
/// A decision only records the status and queues it on each tracker's intake; each tracker's
/// worker releases or drops its own held records once it reaches the decision.
final class ConsentGate: Sendable {
    /// A record waiting for its category to be decided, with the tracker it belongs to.
    fileprivate struct Held: Sendable {
        let record: EventRecord
        /// Its tracker's ``Membership/id``: an identity, not a reference, so a hold keeps no
        /// tracker's records alive.
        let member: Int
    }

    fileprivate struct State: Sendable {
        var statuses: [ConsentCategory: ConsentStatus]
        /// The intake of each tracker given this consent, by membership.
        var intakes: [Int: AsyncStream<Intake.Entry>.Continuation] = [:]
        var nextMember = 0
        // A Deque: the hold drops its oldest record on every track once it is full, which an
        // Array would make O(n).
        /// Records held in memory only, bounded by `heldRecordLimit`.
        var held: Deque<Held> = []
        /// Records a store recovered, held outside the bound: the store keeps them, so memory
        /// running short is no reason to drop them.
        var stored: [Held] = []
    }

    // A Mutex rather than an actor: a decision, a tracker joining and each worker take it
    // synchronously and briefly, and nothing waits or writes to a store while holding it.
    private let state: Mutex<State>
    private let heldRecordLimit: Int
    // The queue alone, not the gate, so the reports end once the consent is gone.
    let dropReports = AsyncQueue<ConsentDropReport>(name: "a consent's drop reports", buffering: .init(adding: ConsentDropReport.add(_:to:)))

    init(statuses: [ConsentCategory: ConsentStatus], heldRecordLimit: Int) {
        state = Mutex(State(statuses: statuses))
        self.heldRecordLimit = heldRecordLimit
    }

    deinit {
        dropReports.finish()
    }

    func status(of category: ConsentCategory) -> ConsentStatus {
        state.withLock { $0.statuses[category, default: .undecided] }
    }

    var heldRecordCount: Int {
        state.withLock { $0.held.count + $0.stored.count }
    }

    /// Sets each of `categories` to `status`, and queues the decision on every tracker's intake.
    func decide(_ categories: [ConsentCategory], _ status: ConsentStatus) {
        let decided = Set(categories)
        state.withLock { state in
            for category in decided {
                state.statuses[category] = status
            }
            // Under the lock, so every intake gets the decisions in one order, and a tracker
            // joining gets either the status or the decision, never neither.
            for intake in state.intakes.values {
                intake.yield(.decide(decided, status))
            }
        }
    }

    /// Makes `intake` receive every decision from now on.
    ///
    /// - Returns: The membership, holding the statuses decided so far.
    func join(_ intake: AsyncStream<Intake.Entry>.Continuation) -> Membership {
        state.withLock { state in
            let id = state.nextMember
            state.nextMember += 1
            state.intakes[id] = intake
            return Membership(gate: self, id: id, statuses: state.statuses)
        }
    }
}

extension ConsentGate {
    /// A tracker's place in a consent, which its worker holds and releases records through.
    struct Membership: Sendable {
        let gate: ConsentGate
        let id: Int
        /// The statuses decided when the tracker joined.
        let statuses: [ConsentCategory: ConsentStatus]

        /// Holds `record`, returning the record dropped for room, if any: the oldest held in
        /// memory only, which may be `record` itself.
        func hold(_ record: EventRecord) -> EventRecord? {
            gate.hold(Held(record: record, member: id))
        }

        /// Takes this tracker's held records of `categories`, in the order they were held.
        func release(_ categories: Set<ConsentCategory>) -> [EventRecord] {
            gate.take(from: id) { categories.contains($0.consentCategory) }
        }

        /// Stops receiving decisions and lets go of this tracker's held records: one a store
        /// keeps stays there for a later launch; one held in memory only is dropped and
        /// reported.
        func leave() {
            gate.state.withLock { _ = $0.intakes.removeValue(forKey: id) }
            var dropped = DroppedRecords()
            let released = gate.take(from: id) { _ in true }
            for record in released where record.deliveryTag == nil {
                dropped.add(record)
            }
            if let timestamps = dropped.timestamps {
                report([.finishedUndecided(recordCount: dropped.count, timestamps: timestamps)])
            }
        }

        /// Reports each of `reports` on ``Consent/dropReports``.
        func report(_ reports: [ConsentDropReport]) {
            for report in reports {
                gate.dropReports.enqueue(report)
            }
        }
    }

    /// Adds `held` to the hold, returning the record dropped to make room, if any.
    fileprivate func hold(_ held: Held) -> EventRecord? {
        state.withLock { state in
            guard held.record.deliveryTag == nil else {
                state.stored.append(held)
                return nil
            }
            guard heldRecordLimit > 0 else { return held.record }
            var dropped: EventRecord?
            if state.held.count == heldRecordLimit {
                dropped = state.held.removeFirst().record
            }
            state.held.append(held)
            return dropped
        }
    }

    /// Removes the records held for `member` that match `isTaken`: those a store recovered,
    /// which were tracked before any held in memory only, then the others, each in order.
    fileprivate func take(from member: Int, where isTaken: (EventRecord) -> Bool) -> [EventRecord] {
        state.withLock { state in
            var taken: [EventRecord] = []
            state.stored.removeAll { held in
                guard held.member == member, isTaken(held.record) else { return false }
                taken.append(held.record)
                return true
            }
            state.held.removeAll { held in
                guard held.member == member, isTaken(held.record) else { return false }
                taken.append(held.record)
                return true
            }
            return taken
        }
    }
}
