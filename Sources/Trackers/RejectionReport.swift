internal import DequeModule
public import Events
public import Foundation

/// Events a tracker rejected because a property broke a constraint declared on it: the event's
/// name, the property and the keyword it broke, how many were rejected and when they were tracked.
///
/// A tracker checks each event on its worker before anything else (`Event`'s `constraintViolation()`),
/// and an event that breaks a constraint is never held by a consent, written to a store or
/// delivered. Each rejection is reported on ``Tracker/rejectionReports``; so is a record a store
/// recovered that breaks a constraint added since, which the store then forgets.
public struct RejectionReport: Sendable, Hashable, CustomStringConvertible {
    /// The rejected events' `Event.name`.
    public var eventName: String
    /// The property and the keyword its value broke.
    public var violation: ConstraintViolation
    /// How many events were rejected for it.
    public var recordCount: Int
    /// The range of times they were tracked in.
    public var timestamps: ClosedRange<Date>

    /// A report of `recordCount` events named `eventName`, tracked within `timestamps`, rejected
    /// for `violation`.
    ///
    /// - Parameters:
    ///   - eventName: The rejected events' name.
    ///   - violation: The property and the keyword its value broke.
    ///   - recordCount: How many events were rejected.
    ///   - timestamps: The range of times they were tracked in.
    public init(eventName: String, violation: ConstraintViolation, recordCount: Int, timestamps: ClosedRange<Date>) {
        self.eventName = eventName
        self.violation = violation
        self.recordCount = recordCount
        self.timestamps = timestamps
    }

    /// `<event>: "<property>" breaks <keyword> (<count> rejected)`.
    public var description: String {
        "\(eventName): \(violation) (\(recordCount) rejected)"
    }
}

extension RejectionReport {
    /// Merges a report into the waiting one of the same event and violation, wherever it waits, so
    /// the reports waiting hold at most one per event, property and keyword: as many as the app
    /// declares constraints, however many events break them.
    static func add(_ report: RejectionReport, to waiting: inout Deque<RejectionReport>) {
        guard let index = waiting.firstIndex(where: { $0.eventName == report.eventName && $0.violation == report.violation }) else {
            waiting.append(report)
            return
        }
        waiting[index] = waiting[index].merged(with: report)
    }

    /// This report and `report`, of the same event and violation, as one: their counts added,
    /// held at `Int.max`, and the range of times spanning both.
    ///
    /// - Parameter report: A later report of the same event and violation.
    /// - Returns: The report counting both.
    package func merged(with report: RejectionReport) -> RejectionReport {
        var merged = self
        merged.recordCount = recordCount.saturatingAdd(report.recordCount)
        merged.timestamps = min(timestamps.lowerBound, report.timestamps.lowerBound) ... max(timestamps.upperBound, report.timestamps.upperBound)
        return merged
    }
}
