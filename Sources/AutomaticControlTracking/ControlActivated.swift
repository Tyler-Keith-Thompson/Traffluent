public import Events
internal import LinkerSets

/// Someone activated the control named ``control``, such as by tapping a button or flipping a
/// switch: what `trackControlsAutomatically(_:)` tracks for each activation it discovers.
///
/// It is `Codable`, so a store keeps it once its `events` list `ControlActivated.self`, and
/// its ``schema`` goes in a tracking plan beside the app's own events. It builds on every
/// platform, so a tracking plan or a collector off Apple platforms can name it too.
public struct ControlActivated: Event, Codable, Hashable {
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
        version: schemaVersion,
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
}

// The record DiscoveredEvent.all finds this event by, of the kind and type @Event's records have:
// the library's own modules don't depend on the macro.
extension ControlActivated: __DiscoverableEvent {
    @LinkerSetEntry(kind: 0x6576_6E74)  // "evnt", the kind Events reads; everyEvent checks it
    private static let discoveryRecord: any __DiscoverableEvent.Type = ControlActivated.self
}
