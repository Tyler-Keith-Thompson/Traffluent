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
/// acknowledged (the delivery was cancelled, or the app ended first) stays in the store.
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
}
