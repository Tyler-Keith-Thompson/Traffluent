import Events

/// A destination that hands `base` each batch with every record transformed, leaving out the
/// records the transform drops: what the destination modifiers return.
///
/// A batch left with no records isn't handed on, as a destination never receives an empty one;
/// it counts as received, so a store still forgets its records once every destination has them.
struct TransformingDestination<Base: Destination>: Destination {
    let base: Base
    /// The record `base` receives in place of the one given, or `nil` to leave it out.
    let transform: @Sendable (EventRecord) -> EventRecord?

    func receive(_ batch: [EventRecord]) async {
        let transformed = batch.compactMap(transform)
        guard !transformed.isEmpty else { return }
        await base.receive(transformed)
    }
}
