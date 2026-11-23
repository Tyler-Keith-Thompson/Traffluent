import Afluent
import Foundation
import Synchronization

/// Observes the app's lifecycle notifications and hands each transition to a
/// ``LifecycleWorker``, doing nothing else on the thread that posts them.
final class LifecycleMonitor: Sendable {
    private let transitions: AsyncStream<LifecycleTransition>.Continuation
    private let center: NotificationCenter
    // A Mutex rather than an actor: a notification's handler can't await, and `cancel()`,
    // `finish()` and `deinit` take the observers out once, briefly.
    private let observers: Mutex<[any NSObjectProtocol]>

    /// Starts `worker` on its own task, and the observation of `center`'s lifecycle
    /// notifications.
    init(worker: LifecycleWorker, center: NotificationCenter) {
        // An AsyncStream, so a handler's hand-off is a yield, safe from any thread, and the worker
        // takes the transitions in the order they were posted.
        let (stream, transitions) = AsyncStream.makeStream(of: LifecycleTransition.self)
        transitions.yield(.started)
        self.transitions = transitions
        self.center = center
        // Detached, so the worker never runs on the actor that started tracking, typically the
        // main actor. On a utility dispatch queue rather than the cooperative pool, as the
        // tracker's own worker is: a version store's read and a record store's synchronize block
        // their thread.
        Task.detached(executorPreference: QueueExecutor.globalQueue(qos: .utility)) {
            await worker.run(stream)
        }
        // Each handler holds the stream's continuation, not the monitor, so releasing the monitor
        // removes them.
        let tokens = LifecycleNotification.all.map { notification in
            center.addObserver(forName: notification.name, object: nil, queue: nil) { _ in
                Self.receive(notification.signal, into: transitions)
            }
        }
        observers = Mutex(tokens)
    }

    deinit {
        stopObserving()
        transitions.finish()
    }

    /// Stops observing; the worker handles what it was handed, then ends.
    func cancel() {
        stopObserving()
        transitions.finish()
    }

    /// Stops observing, then waits for the worker to end the lifecycle.
    func finish() async {
        stopObserving()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if case .terminated = transitions.yield(.finished(done: { continuation.resume() })) {
                continuation.resume()
            }
        }
        transitions.finish()
    }
}

extension LifecycleMonitor {
    /// Hands `transitions` the transition `signal` reports and, leaving the foreground, asks the
    /// system for the time to make the records durable before the app is suspended.
    fileprivate static func receive(_ signal: LifecycleNotification.Signal, into transitions: AsyncStream<LifecycleTransition>.Continuation) {
        switch signal {
        case .enteredForeground:
            transitions.yield(.enteredForeground)
        case .enteredBackground:
            let time = BackgroundTime()
            hand(.enteredBackground(done: time.end), to: transitions, holding: time)
        case .terminated:
            let time = BackgroundTime()
            hand(.terminated(done: time.end), to: transitions, holding: time)
        }
    }

    /// Hands `transitions` the `transition`, holding `time` until the worker calls its `done`.
    private static func hand(_ transition: LifecycleTransition, to transitions: AsyncStream<LifecycleTransition>.Continuation, holding time: BackgroundTime) {
        guard case .enqueued = transitions.yield(transition) else {
            time.end()
            return
        }
        time.begin()
    }

    /// Removes every observer; does nothing the second time.
    private func stopObserving() {
        let tokens = observers.withLock { observers in
            defer { observers = [] }
            return observers
        }
        for token in tokens {
            center.removeObserver(token)
        }
    }
}
