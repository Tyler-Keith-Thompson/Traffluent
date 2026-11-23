/// Lifecycle tracking that `trackLifecycle` started, which goes on until ``cancel()`` or
/// ``finish()`` is called, or the last copy of this value is released.
///
/// Keep it where the app keeps its tracker, such as in its application delegate.
public struct LifecycleObservation: Sendable {
    /// A kind of lifecycle event: pass the ones to track as `trackLifecycle`'s `kinds`.
    public enum Kind: CaseIterable, Hashable, Sendable {
        /// ``ApplicationInstalled``, as tracking starts on a first launch.
        case installed
        /// ``ApplicationUpdated``, as tracking starts on the first launch of a new version.
        case updated
        /// ``ApplicationOpened``, as tracking starts and as the app returns to the foreground.
        case opened
        /// ``ApplicationBackgrounded``, as the app moves to the background.
        case backgrounded
        /// ``ApplicationTerminated``, as the app terminates where the platform reports it, and
        /// as ``LifecycleObservation/finish()`` is called.
        case terminated
    }

    let monitor: LifecycleMonitor

    /// Stops observing the app's lifecycle, tracking nothing more; does nothing if it stopped
    /// already.
    ///
    /// Transitions already observed are still handled, off the caller.
    public func cancel() {
        monitor.cancel()
    }

    /// Ends the app's lifecycle: stops observing it, then tracks ``ApplicationTerminated``,
    /// unless one was tracked already or ``Kind/terminated`` is off, and makes the tracker's
    /// records durable as on backgrounding. Returns once that is done, or at once if tracking
    /// was cancelled.
    ///
    /// Call it where a process with no lifecycle notifications ends, such as a server or a
    /// command-line tool on Linux, before the tracker's own `finish()`.
    public func finish() async {
        await monitor.finish()
    }
}
