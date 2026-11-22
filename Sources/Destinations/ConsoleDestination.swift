public import Events

/// A destination that prints each event on a line of its own: its name, then the value.
public struct ConsoleDestination: Destination {
    /// A destination that prints to standard output.
    public init() {}

    /// Prints each record in `batch`, in order: its event's `Event.name`, a space, and the event's
    /// description.
    ///
    /// - Parameter batch: The records to print.
    public func receive(_ batch: [EventRecord]) async {
        for record in batch {
            print(line(for: record))
        }
    }

    /// The line ``receive(_:)`` prints for `record`.
    package func line(for record: EventRecord) -> String {
        "\(record.name) \(record.event)"
    }
}
