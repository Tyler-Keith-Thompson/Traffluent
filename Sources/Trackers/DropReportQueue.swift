internal import DequeModule
internal import Foundation
internal import Synchronization

/// The drop reports a ``Consent`` has made and no one has read yet, behind
/// ``Consent/dropReports``.
///
/// A held-record-limit report merges into one still waiting right before it, so a full hold
/// adds no report per event while nothing reads them: the reports waiting hold at most one
/// overflow report between any two others, however many events overflow in between. An
/// `AsyncStream`'s continuation would buffer every report, and a dropping buffer policy would
/// lose counts.
final class DropReportQueue: Sendable {
    fileprivate struct State: Sendable {
        var waiting: Deque<ConsentDropReport> = []
        /// The reader waiting for the next report, if one is.
        var reader: CheckedContinuation<ConsentDropReport?, Never>?
        var isFinished = false
    }

    // A Mutex rather than an actor: workers report synchronously, and a reader's cancellation
    // handler, which can't await, takes it too.
    private let state = Mutex(State())

    /// Hands `report` to the waiting reader, or keeps it, merged into a waiting overflow report.
    func report(_ report: ConsentDropReport) {
        let reader: CheckedContinuation<ConsentDropReport?, Never>? = state.withLock { state in
            guard !state.isFinished else { return nil }
            if let reader = state.reader {
                state.reader = nil
                return reader
            }
            if let last = state.waiting.last, let merged = last.merging(report) {
                state.waiting[state.waiting.count - 1] = merged
            } else {
                state.waiting.append(report)
            }
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
    func next() async -> ConsentDropReport? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ConsentDropReport?, Never>) in
                let ready: ConsentDropReport?? = state.withLock { state in
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

extension ConsentDropReport {
    /// This report and `next` as one, when both are held-record-limit drops; otherwise `nil`.
    fileprivate func merging(_ next: ConsentDropReport) -> ConsentDropReport? {
        guard case .heldRecordLimit(let count, let timestamps) = self,
            case .heldRecordLimit(let nextCount, let nextTimestamps) = next
        else { return nil }
        let merged = min(timestamps.lowerBound, nextTimestamps.lowerBound) ... max(timestamps.upperBound, nextTimestamps.upperBound)
        return .heldRecordLimit(recordCount: count + nextCount, timestamps: merged)
    }
}
