internal import DequeModule
public import Events
public import Foundation

/// Records a ``Consent`` dropped before they were delivered, and why.
///
/// A consent reports every drop of a record it held or a store kept on its
/// ``Consent/dropReports``. An event tracked while its category is already denied is never
/// collected, so it isn't reported.
public enum ConsentDropReport: Sendable, Hashable {
    /// `category` was denied, so the `recordCount` records of it that were held or recovered from
    /// a store, tracked within `timestamps`, were dropped.
    case denied(category: ConsentCategory, recordCount: Int, timestamps: ClosedRange<Date>)
    /// The hold was full, so its oldest `recordCount` records, tracked within `timestamps`, were
    /// dropped to make room. Reported as they are dropped, one report counting every drop since
    /// the last report was read; records a store recovered are held
    /// outside the bound, so these never include one.
    case heldRecordLimit(recordCount: Int, timestamps: ClosedRange<Date>)
    /// A tracker finished while `recordCount` of its records, tracked within `timestamps`, were
    /// held in memory only, undecided, so they can't be delivered.
    case finishedUndecided(recordCount: Int, timestamps: ClosedRange<Date>)
}

extension ConsentDropReport {
    /// Merges a held-record-limit report into one still waiting right before it, so a full hold
    /// adds no report per event while nothing reads them: the reports waiting hold at most one
    /// overflow report between any two others, however many events overflow in between.
    static func add(_ report: ConsentDropReport, to waiting: inout Deque<ConsentDropReport>) {
        if let last = waiting.last, let merged = last.merging(report) {
            waiting[waiting.count - 1] = merged
        } else {
            waiting.append(report)
        }
    }

    /// This report and `next` as one, when both are held-record-limit drops: their counts added,
    /// held at `Int.max`, and the range of times spanning both; otherwise `nil`.
    ///
    /// - Parameter next: The report that follows this one.
    /// - Returns: The report counting both, or `nil` when they don't merge.
    package func merging(_ next: ConsentDropReport) -> ConsentDropReport? {
        guard case .heldRecordLimit(let count, let timestamps) = self,
            case .heldRecordLimit(let nextCount, let nextTimestamps) = next
        else { return nil }
        let merged = min(timestamps.lowerBound, nextTimestamps.lowerBound) ... max(timestamps.upperBound, nextTimestamps.upperBound)
        return .heldRecordLimit(recordCount: count.saturatingAdd(nextCount), timestamps: merged)
    }
}
