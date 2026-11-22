public import Events

/// Someone tapped the button labelled `label`.
public struct ButtonTapped: Event, Equatable {
    /// The tapped button's label.
    public var label: String

    /// The event for a tap on the button labelled `label`.
    ///
    /// - Parameter label: The tapped button's label.
    public init(label: String) {
        self.label = label
    }
}
