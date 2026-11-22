public import Destinations
public import Events

/// Delivers every event it tracks to each of its destinations.
///
/// A pipeline is a value: build one where the app starts and pass it to what tracks events.
///
/// ```swift
/// let pipeline = Pipeline(ConsoleDestination())
/// await pipeline.track(SignedUp(plan: "pro"))
/// ```
public struct Pipeline: Sendable {
    // Existentials: one pipeline holds destinations of different types.
    @usableFromInline
    let destinations: [any Destination]

    /// A pipeline delivering to `destinations`, in the order given.
    ///
    /// - Parameter destinations: Where each tracked event goes.
    public init(_ destinations: any Destination...) {
        self.destinations = destinations
    }

    /// Delivers `event` to every destination, one after another, in order.
    ///
    /// - Parameter event: The event to deliver.
    /// - Complexity: O(*n*) deliveries, where *n* is the number of destinations.
    @inlinable
    public func track(_ event: some Event) async {
        for destination in destinations {
            await destination.receive(event)
        }
    }
}
