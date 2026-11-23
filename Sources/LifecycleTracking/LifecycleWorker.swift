import Events
import Logging
import Trackers

/// The one consumer of a ``LifecycleMonitor``'s transitions: it decides which lifecycle events
/// each transition tracks, and makes the tracker's records durable as the app leaves the
/// foreground, off the thread that posted the notification.
struct LifecycleWorker: Sendable {
    /// Where the app is, so each event tracks once per transition.
    enum Phase {
        case foreground
        case background
        case terminated
    }

    let tracker: Tracker
    let kinds: Set<LifecycleObservation.Kind>
    let version: String?
    let versionStore: any VersionStore
    let callSite: SourceLocation

    private static let logger = Logger(label: "LifecycleTracking.LifecycleWorker")

    /// Handles each transition in order until the transitions end or the lifecycle finishes.
    func run(_ transitions: AsyncStream<LifecycleTransition>) async {
        // Tracking starts as the app launches, in the foreground.
        var phase = Phase.foreground
        for await transition in transitions {
            switch transition {
            case .started:
                trackVersionChange()
                track(.opened, ApplicationOpened(fromBackground: false))
            case .enteredForeground:
                guard phase == .background else { continue }
                phase = .foreground
                track(.opened, ApplicationOpened(fromBackground: true))
            case .enteredBackground(let done):
                defer { done() }
                guard phase == .foreground else { continue }
                phase = .background
                track(.backgrounded, ApplicationBackgrounded())
                await makeRecordsDurable()
            case .terminated(let done):
                defer { done() }
                guard phase != .terminated else { continue }
                phase = .terminated
                track(.terminated, ApplicationTerminated())
                await makeRecordsDurable()
            case .finished(let done):
                defer { done() }
                guard phase != .terminated else { return }
                phase = .terminated
                track(.terminated, ApplicationTerminated())
                await makeRecordsDurable()
                return
            }
        }
    }
}

extension LifecycleWorker {
    /// Tracks an install or an update, if the version saved says so, having saved this one.
    fileprivate func trackVersionChange() {
        guard let version else { return }
        let change: VersionChange
        do {
            change = VersionChange(previous: try versionStore.load(), current: version)
            // Saved before tracking, so a version that can't be saved tracks nothing, rather than
            // the same install or update on every launch. Saved whatever `kinds` holds, so turning
            // a kind on later doesn't report an install that happened long before.
            if change != .unchanged {
                try versionStore.save(version)
            }
        } catch {
            Self.logger.error("Tracked neither an install nor an update: the version store failed: \(error)")
            return
        }
        switch change {
        case .installed:
            track(.installed, ApplicationInstalled(version: version))
        case .updated(let previousVersion):
            track(.updated, ApplicationUpdated(previousVersion: previousVersion, version: version))
        case .unchanged:
            break
        }
    }

    /// Tracks `event` if `kind` is on, at the call site that started tracking.
    fileprivate func track(_ kind: LifecycleObservation.Kind, _ event: some Event) {
        guard kinds.contains(kind) else { return }
        tracker.track(event, file: callSite.file, fileID: callSite.fileID, function: callSite.function, line: callSite.line, column: callSite.column)
    }

    /// Waits for the tracker's worker to write every record tracked so far to its store, then
    /// makes the store durable against power loss.
    fileprivate func makeRecordsDurable() async {
        await tracker.flush()
        tracker.store?.synchronize()
    }
}
