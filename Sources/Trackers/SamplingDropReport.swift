internal import DequeModule
public import Foundation

/// Events a tracker's ``Sampler``s left out: the event's name, how many were left out and when
/// they were tracked.
///
/// A sampled-out event is dropped on the tracker's worker before it is held by a consent, written
/// to a store or delivered, and reported on ``Tracker/samplingDropReports``, so the drops are
/// counted rather than silent.
public struct SamplingDropReport: Sendable, Hashable, CustomStringConvertible {
    /// The dropped events' `Event.name`.
    public var eventName: String
    /// How many events were dropped.
    public var recordCount: Int
    /// The range of times they were tracked in.
    public var timestamps: ClosedRange<Date>

    /// A report of `recordCount` events named `eventName`, tracked within `timestamps`, that
    /// samplers left out.
    ///
    /// - Parameters:
    ///   - eventName: The dropped events' name.
    ///   - recordCount: How many events were dropped.
    ///   - timestamps: The range of times they were tracked in.
    public init(eventName: String, recordCount: Int, timestamps: ClosedRange<Date>) {
        self.eventName = eventName
        self.recordCount = recordCount
        self.timestamps = timestamps
    }

    /// `<event>: <count> sampled out`.
    public var description: String {
        "\(eventName): \(recordCount) sampled out"
    }
}

extension SamplingDropReport {
    /// Merges a report into the waiting one of the same event, wherever it waits, so the reports
    /// waiting hold at most one per event type, however many events are dropped.
    static func add(_ report: SamplingDropReport, to waiting: inout Deque<SamplingDropReport>) {
        guard let index = waiting.firstIndex(where: { $0.eventName == report.eventName }) else {
            waiting.append(report)
            return
        }
        let merged = waiting[index]
        waiting[index].recordCount = merged.recordCount + report.recordCount
        waiting[index].timestamps = min(merged.timestamps.lowerBound, report.timestamps.lowerBound) ... max(merged.timestamps.upperBound, report.timestamps.upperBound)
    }
}
