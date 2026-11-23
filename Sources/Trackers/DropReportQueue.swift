internal import DequeModule
internal import Foundation
internal import Synchronization

/// A report a ``DropReportQueue`` keeps until it is read, which decides how it joins the reports
/// already waiting.
protocol QueuedReport: Sendable {
    /// Adds `report` to `waiting`, the reports not yet read, oldest first: appended, or merged into
    /// one of them.
    static func add(_ report: Self, to waiting: inout Deque<Self>)
}

/// The reports a ``Consent`` or a tracker has made and no one has read yet, behind
/// ``Consent/dropReports`` and ``Tracker/rejectionReports``.
///
/// Each kind of report merges into the reports waiting as its ``QueuedReport/add(_:to:)`` says,
/// so a burst of drops adds no report per event while nothing reads them. An `AsyncStream`'s
/// continuation would buffer every report, and a dropping buffer policy would lose counts.
final class DropReportQueue<Report: QueuedReport>: Sendable {
    fileprivate struct State: Sendable {
        var waiting: Deque<Report> = []
        /// The reader waiting for the next report, if one is.
        var reader: CheckedContinuation<Report?, Never>?
        var isFinished = false
    }

    // A Mutex rather than an actor: workers report synchronously, and a reader's cancellation
    // handler, which can't await, takes it too.
    private let state = Mutex(State())

    /// Hands `report` to the waiting reader, or keeps it, merged as its kind merges.
    func report(_ report: Report) {
        let reader: CheckedContinuation<Report?, Never>? = state.withLock { state in
            guard !state.isFinished else { return nil }
            if let reader = state.reader {
                state.reader = nil
                return reader
            }
            Report.add(report, to: &state.waiting)
            return nil
        }
        reader?.resume(returning: report)
    }

    /// Ends the reports after those waiting.
    func finish() {
        let reader = state.withLock { state in
            state.isFinished = true
            defer { state.reader = nil }
            return state.reader
        }
        reader?.resume(returning: nil)
    }

    /// The next report, waiting for one; `nil` once finished and read, or when the reading task
    /// is cancelled.
    func next() async -> Report? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Report?, Never>) in
                let ready: Report?? = state.withLock { state in
                    // Checked under the lock the cancellation handler takes too: a cancellation
                    // either came first, or finds this reader waiting.
                    guard !Task.isCancelled else { return .some(nil) }
                    if !state.waiting.isEmpty {
                        return .some(state.waiting.removeFirst())
                    }
                    guard !state.isFinished else { return .some(nil) }
                    state.reader = continuation
                    return nil
                }
                if let ready {
                    continuation.resume(returning: ready)
                }
            }
        } onCancel: {
            let reader = state.withLock { state in
                defer { state.reader = nil }
                return state.reader
            }
            reader?.resume(returning: nil)
        }
    }
}

extension ConsentDropReport: QueuedReport {
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

    /// This report and `next` as one, when both are held-record-limit drops; otherwise `nil`.
    fileprivate func merging(_ next: ConsentDropReport) -> ConsentDropReport? {
        guard case .heldRecordLimit(let count, let timestamps) = self,
            case .heldRecordLimit(let nextCount, let nextTimestamps) = next
        else { return nil }
        let merged = min(timestamps.lowerBound, nextTimestamps.lowerBound) ... max(timestamps.upperBound, nextTimestamps.upperBound)
        return .heldRecordLimit(recordCount: count + nextCount, timestamps: merged)
    }
}
