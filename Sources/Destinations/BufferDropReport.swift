public import Foundation

/// A batch a destination's full buffer dropped before the destination received it.
///
/// `deliver(to:batchBufferLimit:bufferDropReporter:)` yields one for every batch it drops. Of the
/// batch's records, those a tracker's store keeps (``storedRecordCount``) are not lost: the
/// delivery reads them back from the store and hands them to this destination alone once it has
/// caught up. They wait in the store for a later launch instead when the store can't read them
/// back, or when the destination falls so far behind that the delivery forgets the batch (it
/// keeps track of ten buffers' worth, and logs each it forgets). The others, kept in memory only,
/// are lost.
public struct BufferDropReport: Sendable, Hashable {
    /// The destination whose buffer dropped the batch: its position among the delivery's
    /// destinations, from 0.
    public let destinationIndex: Int
    /// How many records the batch held.
    public let recordCount: Int
    /// When the batch's records were tracked, from the earliest to the latest.
    public let timestamps: ClosedRange<Date>
    /// How many of the batch's records a store keeps, which are not lost: read back for the
    /// destination in this run, or left in the store for a later launch.
    public let storedRecordCount: Int

    /// A report that the buffer of the destination at `destinationIndex` dropped a batch of
    /// `recordCount` records tracked within `timestamps`, `storedRecordCount` of them kept by a
    /// store.
    ///
    /// - Parameters:
    ///   - destinationIndex: The destination's position among the delivery's destinations.
    ///   - recordCount: How many records the batch held.
    ///   - timestamps: When its records were tracked.
    ///   - storedRecordCount: How many of them a store keeps.
    public init(destinationIndex: Int, recordCount: Int, timestamps: ClosedRange<Date>, storedRecordCount: Int) {
        self.destinationIndex = destinationIndex
        self.recordCount = recordCount
        self.timestamps = timestamps
        self.storedRecordCount = storedRecordCount
    }
}
