/// An event type found in the running program: one declared with `@Event`, or one of the
/// library's own events, with its schema.
///
/// ``all`` lists every one the program links, from every module, so a store or a tracking plan
/// can be built from it with no list to keep: `SegmentStore()`, `DatabaseStore(database:)` and
/// `TrackingPlan()` each use it.
///
/// ```swift
/// import Traffluent
///
/// @Event(name: "signed_up")
/// struct SignedUp {
///     var plan: String
/// }
///
/// DiscoveredEvent.all.map { $0.type.name }
/// // ["ApplicationBackgrounded", ..., "SessionStarted", "signed_up"]
/// ```
///
/// Each `@Event` struct is discovered, wherever it is declared, unless it is generic or nested in
/// a generic type, as neither can hold the record `@Event` places in the binary; the macro notes
/// each one where it is declared. One declared in an extension of a generic type doesn't compile.
/// The library's own events are discovered too: `SessionStarted`, `SessionEnded`,
/// `ScreenViewed`, `ControlActivated` and the `Application` events of `LifecycleTracking`, once
/// their modules are linked. An event that conforms to ``Event`` by hand, without `@Event`, isn't:
/// list it beside the discovered ones, `DiscoveredEvent.all.map(\.type) + [Legacy.self]`.
///
/// ## Limits
///
/// - On Linux and the other ELF platforms, only the image that links `Events` is read, which is
///   the whole program as SwiftPM and Bazel link Swift there. Events in a library loaded on its
///   own, a dynamic library or a plugin, aren't found.
/// - An object file in a static archive that nothing references brings no record into the
///   program: the linker leaves it out. That happens with CocoaPods' static libraries, a static
///   XCFramework, or a Bazel library with `alwayslink = False`. SwiftPM, and Bazel's
///   `alwayslink = True`, link every object file.
/// - ``all`` holds the events of the images loaded when it is called; a framework loaded later
///   adds its events from then on.
/// - Object formats other than Mach-O and ELF, such as COFF on Windows and WebAssembly's, have no
///   events found: ``all`` is empty there.
public struct DiscoveredEvent: Sendable {
    /// The event's type.
    public let type: any (Event & Codable).Type

    /// The event's schema.
    public let schema: EventSchema

    init(type: any (Event & Codable).Type, schema: EventSchema) {
        self.type = type
        self.schema = schema
    }

    /// Every event type the program links, ordered by the UTF-8 bytes of their names, then by
    /// version, then by the types' fully qualified names.
    ///
    /// Two types may share a name: a store or a plan built from the list refuses them, as it
    /// would the same types listed by hand.
    ///
    /// - Complexity: O(*n* log *n*) in the events, after a walk of the program's loaded images.
    public static var all: [DiscoveredEvent] {
        // One type can have two records: one written by hand beside the macro's, or a record's
        // object file linked into one image twice. A store or plan built from the list would refuse
        // the second as a duplicate name, so each type is listed once.
        var seen = Set<ObjectIdentifier>()
        return __EventDiscovery.events()
            .filter { seen.insert(ObjectIdentifier($0.type)).inserted }
            .map { (event: $0, typeName: String(reflecting: $0.type)) }
            .sorted { $0.event.precedes($1.event, typeNames: ($0.typeName, $1.typeName)) }
            .map(\.event)
    }
}

extension DiscoveredEvent {
    /// Whether this event comes before `other`: by name, then version, then type name.
    fileprivate func precedes(_ other: DiscoveredEvent, typeNames: (String, String)) -> Bool {
        let (name, otherName) = (type.name, other.type.name)
        guard name == otherName else { return name.utf8.lexicographicallyPrecedes(otherName.utf8) }
        guard type.schemaVersion == other.type.schemaVersion else { return type.schemaVersion < other.type.schemaVersion }
        return typeNames.0.utf8.lexicographicallyPrecedes(typeNames.1.utf8)
    }
}
