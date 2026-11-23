public import Instrumentation

/// Adds to the context of each event a tracker tracks, before the record is delivered.
///
/// An enricher reads and sets values through typed `ServiceContextKey`s, so what it adds keeps its
/// type all the way to the destinations:
///
/// ```swift
/// enum SessionKey: ServiceContextKey {
///     typealias Value = String
/// }
///
/// let session = Enricher { context in
///     context[SessionKey.self] = "s-42"
/// }
/// let tracker = Tracker(enrichers: [session])
/// ```
///
/// A tracker's worker runs its enrichers in order, on the context `track` took from
/// `ServiceContext.current` when the event was tracked: an enricher sees what earlier ones set,
/// and may override a value the caller's context already holds. It runs on the worker, not the
/// tracking caller's thread, so it sees the caller's context only, not its other task-local
/// values or its actor.
public struct Enricher: Sendable {
    private let enrich: @Sendable (inout ServiceContext) -> Void

    /// An enricher that changes each record's context with `enrich`.
    ///
    /// - Parameter enrich: Sets the values it adds on the context it is given. It runs on the
    ///   tracker's worker for every event, in order, so a slow one delays every record after it.
    public init(_ enrich: @escaping @Sendable (inout ServiceContext) -> Void) {
        self.enrich = enrich
    }

    /// Changes `context` as this enricher does.
    ///
    /// - Parameter context: The context to add to.
    public func callAsFunction(_ context: inout ServiceContext) {
        enrich(&context)
    }
}
