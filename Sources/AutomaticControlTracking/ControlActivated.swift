public import Events
public import Persistence

/// Someone activated the control named ``control``, such as by tapping a button or flipping a
/// switch: what `trackControlsAutomatically(_:)` tracks for each activation it discovers.
///
/// It is `BinaryCodable`, so a store keeps it once its `events` list `ControlActivated.self`, and
/// its ``schema`` goes in a tracking plan beside the app's own events. It builds on every
/// platform, so a tracking plan or a collector off Apple platforms can name it too.
public struct ControlActivated: Event, BinaryCodable, Hashable {
    /// The activated control's name: its accessibility identifier, unless the predicate given to
    /// `trackControlsAutomatically(_:)` named it otherwise.
    public var control: String

    /// The control's kind: the first public UIKit class it is an instance of, such as
    /// `"UIButton"` or `"UISwitch"`.
    public var kind: String

    /// The schema of a control activation: version 1, collected for analytics, with two
    /// properties, the control's name and its kind.
    public static let schema = EventSchema(
        name: name,
        version: 1,
        consentCategory: consentCategory,
        properties: [
            EventSchema.Property(name: "control", typeName: "String", isOptional: false),
            EventSchema.Property(name: "kind", typeName: "String", isOptional: false),
        ]
    )

    /// The event for an activation of the control named `control`, of kind `kind`.
    ///
    /// - Parameters:
    ///   - control: The control's name.
    ///   - kind: The control's kind, such as `"UIButton"`.
    public init(control: String, kind: String) {
        self.control = control
        self.kind = kind
    }

    /// Writes the control's name, then its kind, to `encoder`.
    ///
    /// - Parameter encoder: Where the bytes go.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(control)
        encoder.encode(kind)
    }

    /// Reads the control's name, then its kind, from `decoder`.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: `BinaryDecodingError` when the bytes don't hold a name and a kind.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        control = try decoder.decode()
        kind = try decoder.decode()
    }
}
