public import Events

/// A collector batch as ``CollectorBatchDecoder/batch(from:)`` reads it: the records it read back,
/// and the ones it couldn't.
public struct DecodedCollectorBatch: Sendable {
    /// The records read back, in the body's order.
    public var records: [EventRecord]
    /// The records that couldn't be read, in the body's order.
    public var undecodedRecords: [UndecodedRecord]

    /// A batch of `records`, and the reports of `undecodedRecords`.
    ///
    /// - Parameters:
    ///   - records: The records read back.
    ///   - undecodedRecords: The records that couldn't be read.
    public init(records: [EventRecord], undecodedRecords: [UndecodedRecord]) {
        self.records = records
        self.undecodedRecords = undecodedRecords
    }
}
