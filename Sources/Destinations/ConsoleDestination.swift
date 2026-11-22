public import Events

/// A destination that prints each event on a line of its own: its name, then the value.
public struct ConsoleDestination: Destination {
    /// A destination that prints to standard output.
    public init() {}

    /// Prints `event`: its type's `Event.name`, a space, and the value's description.
    public func receive(_ event: some Event) async {
        print(line(for: event))
    }

    /// The line ``receive(_:)`` prints for `event`.
    package func line<E: Event>(for event: E) -> String {
        "\(E.name) \(event)"
    }
}
