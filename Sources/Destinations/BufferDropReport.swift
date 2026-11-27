import DequeModule
public import Foundation

/// Batches a destination's full buffer dropped before the destination received them.
///
/// A delivery reports each batch it drops on its ``Delivery/bufferDropReports``. Reports no one
/// has read yet merge, one per destination: a later drop adds its counts to the destination's
/// waiting report and widens its timestamps, so a report may count several batches. Of the
/// batches' records, those a tracker's store keeps (``storedRecordCount``) are not lost: the
/// delivery reads them back from the store and hands them to this destination alone once it has
/// caught up. They wait in the store for a later launch instead when the store can't read them
/// back, or when the destination falls so far behind that the delivery forgets the batch (it
/// keeps track of ten buffers' worth, and logs each it forgets). The others, kept in memory only,
/// are lost.
public struct BufferDropReport: Sendable, Hashable {
    /// The destination whose buffer dropped the batches: its position among the delivery's
    /// destinations, from 0.
    public let destinationIndex: Int
    /// How many records the batches held, held at `Int.max`.
    public let recordCount: Int
    /// When the batches' records were tracked, from the earliest to the latest.
    public let timestamps: ClosedRange<Date>
    /// How many of the batches' records a store keeps, which are not lost: read back for the
    /// destination in this run, or left in the store for a later launch. Held at `Int.max`.
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

extension BufferDropReport {
    /// Merges a report into the waiting one of the same destination, wherever it waits, so the
    /// reports waiting hold at most one per destination, however many batches its buffer drops.
    static func add(_ report: BufferDropReport, to waiting: inout Deque<BufferDropReport>) {
        guard let index = waiting.firstIndex(where: { $0.destinationIndex == report.destinationIndex }) else {
            waiting.append(report)
            return
        }
        waiting[index] = waiting[index].merged(with: report)
    }

    /// This report and `report`, of the same destination, as one: their record counts and stored
    /// record counts added, each held at `Int.max`, and the range of times spanning both.
    ///
    /// - Parameter report: A later report of the same destination.
    /// - Returns: The report counting both.
    package func merged(with report: BufferDropReport) -> BufferDropReport {
        BufferDropReport(
            destinationIndex: destinationIndex,
            recordCount: recordCount.saturatingAdd(report.recordCount),
            timestamps: min(timestamps.lowerBound, report.timestamps.lowerBound) ... max(timestamps.upperBound, report.timestamps.upperBound),
            storedRecordCount: storedRecordCount.saturatingAdd(report.storedRecordCount)
        )
    }
}
