public import Afluent
public import AsyncQueues

/// The work of delivering a sequence's batches to destinations, made by `deliver(to:)`, and the
/// reports of the batches their full buffers drop.
///
/// ```swift
/// let delivery = tracker.records.batch().deliver(to: collector)
/// let reports = delivery.bufferDropReports
/// Task {
///     for await report in reports {
///         logger.warning("A full buffer dropped batches: \(report)")
///     }
/// }
/// try await delivery.execute()
/// ```
///
/// A delivery holds its Afluent unit of work as ``work``: nothing runs until it is executed,
/// each execution reads the sequence again, and cancelling it is permanent. ``execute(priority:)``,
/// ``run(priority:)`` and ``cancel()`` act on ``work``; compose it through ``work``
/// (`delivery.work.retry(1)`). A unit of work built on ``work`` (a retry, a `share()`, a stored
/// `subscribe()`) holds the delivery's reports as a copy of the delivery does, so they stay open
/// while it lives. Read ``bufferDropReports`` from the delivery, not from what wraps it.
// A struct holding its unit of work beside its reports, rather than:
// - a type conforming to AsynchronousUnitOfWork itself: Afluent's conformance machinery (state,
//   _operation) is for Afluent's own types only (AFLU-50), and outside conformances stop
//   compiling in 2.0;
// - a pair of work and reports with no forwarding, which would make every call site
//   `.deliver(to:).work.execute()`;
// - a reporter the caller makes and passes in, which a second reader of could trap on, and which
//   isn't the delivery handing out its own reports.
public struct Delivery: Sendable {
    /// The unit of work that delivers: executing it runs the delivery.
    public let work: DeferredTask<Void>
    /// A report of the batches each destination's full buffer drops, in the order they are
    /// dropped.
    ///
    /// Reports no one has read yet merge, one per destination: a destination's later drops add
    /// their record counts to its waiting report and widen its timestamps, so the reports waiting
    /// are at most one per destination, and a late reader still learns every count lost. The
    /// sequence ends once this delivery, every copy of it and every unit of work built on
    /// ``work`` are gone, their executions have returned, and every report has been read. Read
    /// the sequence into a constant before starting the task that reads it, so the task holds the
    /// reports and not the delivery.
    ///
    /// One task reads the reports at a time. The first iterator to read holds them until its
    /// iteration ends or it is released; a second reader meanwhile waits its turn, logging a
    /// warning once, then reads on from the next report, so the first gets every report in
    /// order. A reader cancelled while it waits returns `nil`.
    public let bufferDropReports: AsyncQueue<BufferDropReport>

    /// The delivery `work` runs, whose buffers report each drop to `reports`.
    init(work: DeferredTask<Void>, reports: AsyncQueue<BufferDropReport>) {
        self.work = work
        bufferDropReports = reports
    }

    /// Runs the delivery and waits for it: ``work``'s `execute(priority:)`.
    ///
    /// - Parameter priority: The priority of the task the delivery runs in.
    /// - Throws: What the sequence throws, or `CancellationError` when the delivery is cancelled.
    public func execute(priority: TaskPriority? = nil) async throws {
        try await work.execute(priority: priority)
    }

    /// Runs the delivery without waiting for it: ``work``'s `run(priority:)`.
    ///
    /// - Parameter priority: The priority of the task the delivery runs in.
    public func run(priority: TaskPriority? = nil) {
        work.run(priority: priority)
    }

    /// Cancels the delivery, for good: ``work``'s `cancel()`.
    public func cancel() {
        work.cancel()
    }
}

/// The buffer-drop reports a delivery's buffers share, ended once the delivery's work is gone.
final class BufferDropReporter: Sendable {
    let reports = AsyncQueue<BufferDropReport>(name: "a delivery's buffer-drop reports", buffering: .init(adding: BufferDropReport.add(_:to:)))

    deinit {
        reports.finish()
    }

    func report(_ report: BufferDropReport) {
        reports.enqueue(report)
    }
}
