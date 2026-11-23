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
