/// Where a store keeps a record until it is delivered: the store, and the record's position in it.
///
/// A store tags each record it keeps (``EventRecord/deliveryTag``). A delivery tells the store,
/// through the tags of a batch's records, when it is about to hand them to destinations and once
/// every destination has received them, so the store keeps each record exactly until then.
public struct DeliveryTag: Sendable {
    /// The store keeping the record.
    public let acknowledger: any Acknowledger
    /// The record's position in that store, in whatever numbering the store chooses.
    public let position: UInt64

    /// The tag of the record at `position` in `acknowledger`.
    ///
    /// - Parameters:
    ///   - acknowledger: The store keeping the record.
    ///   - position: The record's position in that store.
    public init(acknowledger: any Acknowledger, position: UInt64) {
        self.acknowledger = acknowledger
        self.position = position
    }
}

/// What keeps records until their delivery is acknowledged: a store, as a delivery sees it.
///
/// A delivery calls ``willDeliver(_:)`` with a batch's positions in the store before it hands the
/// batch, less the records the store says to hold back, to any destination, and
/// ``acknowledge(_:)`` once every destination has received it. A batch that is never
/// acknowledged (the delivery was cancelled, or the app ended first) stays in the store. When a
/// destination's full buffer drops a batch, the delivery reads its records back with
/// ``records(at:)`` once that destination has caught up, hands them to it, and acknowledges only
/// the records every destination received.
///
/// The requirement on classes lets a delivery tell the stores of a batch's records apart by
/// identity.
public protocol Acknowledger: AnyObject, Sendable {
    /// The records at `positions` are about to be handed to destinations.
    ///
    /// A store that keeps records across runs notes this durably, so a record it recovers after
    /// the app ended mid-delivery comes back with ``EventRecord/isRedelivered`` set. A record it
    /// couldn't note (the write failed) it returns: the delivery holds that record back, rather
    /// than risk sending it twice unannounced, and the store keeps it for a later delivery.
    ///
    /// - Parameter positions: The positions of a batch's records in this store, in batch order.
    /// - Returns: The positions of the records the delivery must hold back; empty when it may
    ///   deliver them all.
    func willDeliver(_ positions: [UInt64]) -> Set<UInt64>

    /// Every destination has received the records at `positions`, so the store can forget them.
    ///
    /// - Parameter positions: The positions of a batch's records in this store, in batch order.
    func acknowledge(_ positions: [UInt64])

    /// The records this store still keeps at `positions`, read back for a destination whose
    /// delivery buffer dropped them before it received them.
    ///
    /// A delivery calls it once that destination has caught up, hands it the records returned,
    /// and counts its receipt towards ``acknowledge(_:)`` for those records alone. A position the
    /// store no longer keeps (its bound dropped the record, which it reports) gives no record, and
    /// neither does any position when the store can't read records back, as with the default
    /// implementation. The delivery never acknowledges a record it couldn't hand to every
    /// destination, so a store that still keeps one delivers it on a later launch, with
    /// ``EventRecord/isRedelivered`` set.
    ///
    /// A store of your own should implement it. Without it, the default returns no records, so a
    /// batch a full buffer dropped isn't sent again in this run: the destination whose buffer
    /// dropped it never gets it in this run, every destination gets it again on the next launch,
    /// marked redelivered, and the store holds it until then, toward its bound.
    ///
    /// The delivery gives each record returned the ``EventRecord/isRedelivered``, the
    /// sensitive-value visibility and the `ServiceContext` the record had when the buffer dropped
    /// it, so a store needn't keep them. A record tagged with another store is ignored.
    ///
    /// - Parameter positions: The positions of records in this store a delivery handed to
    ///   destinations.
    /// - Returns: The records kept at those positions, each tagged with its ``DeliveryTag``
    ///   naming this store, in any order.
    func records(at positions: [UInt64]) -> [EventRecord]
}

extension Acknowledger {
    /// No records: a store that can't read its records back keeps those of a batch a
    /// destination's full buffer dropped for a later launch to deliver.
    ///
    /// - Parameter positions: The positions of the records asked for.
    /// - Returns: An empty array.
    public func records(at positions: [UInt64]) -> [EventRecord] {
        []
    }
}
