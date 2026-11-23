internal import Events
internal import Persistence

/// Where a tracker's records go once they may be delivered: written to its store, if it has one,
/// then sent to its records.
struct RecordSink: Sendable {
    let subscription: Subscription
    let store: (any RecordStore)?

    /// Writes `record` to the store, unless a store already keeps it, then sends it.
    func send(_ record: EventRecord) {
        // A tagged record came from the store (recovered from an earlier run), so it is already
        // written; writing it again would deliver it twice.
        guard record.deliveryTag == nil, let store else {
            subscription.send(record)
            return
        }
        subscription.send(store.append(record))
    }
}
