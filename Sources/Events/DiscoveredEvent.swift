internal import LinkerSetsRuntime

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
/// - An object file in a static archive that nothing references brings no record into the
///   program: the linker leaves it out, the library's own events' files included. SwiftPM links
///   every object file, and so does Bazel: from rules_swift 3.0, `swift_library` is
///   `alwayslink = True` unless a target says otherwise, and rules_swift_package_manager sets it
///   on every target of a package. Apple's linker, given `-ObjC`, also loads each member that
///   declares a Swift type or a protocol conformance, though not one holding only an extension
///   that adds members; every `@Event` declares a struct. A static library or static XCFramework
///   linked without `-ObjC`, or a Bazel library with `alwayslink = False` on Linux, leaves its
///   unreferenced events out. Link such a library whole
///   (`-force_load` on Apple platforms, `--whole-archive` on Linux) to have its events found.
/// - ``all`` holds the events of the images loaded when it is called: the program and the
///   dynamic libraries it links. A library opened later with `dlopen` adds its events from then on.
/// - A library that loads or unloads while ``all`` is read is either read whole or left out of
///   that read. On Apple platforms one that dyld adds before the read starts is found; on Linux a
///   `dlopen` or `dlclose` waits for the read, so the library is missed. The next read sees it.
/// - Don't `dlclose` a library that declares events while the process runs. On Apple platforms
///   dyld keeps it mapped and its events are still found. On Linux the loader unmaps it while the
///   Swift runtime keeps its types registered, and the process can crash later. Keep plug-ins
///   open, or open them with `RTLD_NODELETE`.
/// - A module that declares events, linked into two images, lists each of its events twice, and
///   stores and plans refuse the duplicate. Link each such module into one image.
/// - Two events of one name in one linked image, the modules linked statically into one executable
///   or library, fail to build: `@Event` gives each record a symbol named for the event's name,
///   which the compiler or the linker refuses to define twice. Separate images are never compared,
///   so a name shared with a dynamic library, a library opened with `dlopen`, or a module linked
///   into two images is found only here, and a store or plan built from ``all`` refuses it. So is
///   one declared inside a `private` or `fileprivate` type, whose symbol is local to its file.
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
    /// Two types may share a name when they sit in separate images, or one is in a private type,
    /// which the build doesn't compare: a store or a plan built from the list refuses them, as it
    /// would the same types listed by hand. The fully qualified name of a type in a private scope
    /// holds an address that changes between launches, so the order of such types of one name and
    /// version, and the names a store's or plan's error gives for them, can change too.
    ///
    /// - Complexity: O(*n* log *n*) in the events, after a walk of the program's loaded images.
    public static var all: [DiscoveredEvent] {
        // One type can have two records: one written by hand beside the macro's, or a record's
        // object file linked into one image twice. A store or plan built from the list would refuse
        // the second as a duplicate name, so each type is listed once.
        var seen = Set<ObjectIdentifier>()
        return LinkerSet<any __DiscoverableEvent.Type>(kind: .events).values
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
            .map { DiscoveredEvent(type: $0, schema: $0.schema) }
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
