/// What the app's lifecycle notifications, and ``LifecycleObservation``, hand the
/// ``LifecycleWorker``, in the order they happen.
enum LifecycleTransition: Sendable {
    /// Tracking started: the app launched.
    case started
    /// The app returned to the foreground.
    case enteredForeground
    /// The app moved to the background; `done` is called once the records are durable.
    case enteredBackground(done: @Sendable () -> Void)
    /// The app is terminating; `done` is called once the records are durable.
    case terminated(done: @Sendable () -> Void)
    /// ``LifecycleObservation/finish()``: the app's lifecycle ends, and `done` is called once
    /// the records are durable.
    case finished(done: @Sendable () -> Void)
}
