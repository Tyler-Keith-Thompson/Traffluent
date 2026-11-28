package import Events
import Foundation
package import Instrumentation

// Which context keys a store keeps (TRAF-145): a fixed allowlist in the record map, as TRAF-122
// began with the session. A record recovered after a relaunch must reach a destination as it was
// tracked: under its first send's session, weighted by the rate it was sampled at, and attributed
// to the screen, app, device, system, locale and network it was tracked on, not to the run that
// uploads it. None of those but the session identifies anyone, and the session's place on disk is
// D4's amendment. Everything else in a context stays in memory: VendorIdentifierKey above all,
// which D4 says Traffluent never stores; an adopter's own keys, whose values the library can't
// vouch for (an account ID); and a trace's span, which ended with the run that tracked it. A key
// joins the list by a decision of its own, here and in the stores' docs, never by conforming to
// something.
//
// The keys live in Events so that this module can name them. Rejected:
// - a registry of persisted keys that conform to a protocol and are found by LinkerSets, as events
//   are: Trackers and StandardContext would build swift-syntax to write the records, and any key,
//   an adopter's identifier too, could reach the disk by conforming;
// - a store parameter listing the keys: the default store can't name keys of modules above it, so
//   `SegmentStore()` would keep none, and forgetting the list loses sample rates silently;
// - Codable conformances on the key values, written by the CBOR encoder as they are: a public
//   conformance fixes the format outside this module, and a synthesized enum's form (an empty map
//   under the case's name) is no format to keep;
// - the type's mangled name as each member's key, read back with `_typeByName`: renaming or moving
//   a type would orphan what is on disk, and the format would be Swift's ABI;
// - each key a member of the record map itself, beside `session`: recovery looks each one up in
//   every record, which made recovering a record with no context 21% slower in instructions; in
//   one `context` map, such a record costs one lookup more than before.
// The session stays where TRAF-122 put it, so its records read as they did and cost what they did.
//
// Each value is written in a form of its own, below, and read back strictly: a member that is
// there but holds anything else, null included, makes the record undecodable (dropped with a
// report, D9), as a malformed session does; only a form factor's or a network's name that no case
// has reads as its key absent, below. A record without a member, as releases before
// TRAF-145 (or TRAF-122, for the session) wrote, reads back without that key. A `context` map's
// member of another name is skipped, as the record map's are.

/// The keys of a record's context a store keeps beside the record: its session as a member of
/// the record map (`RecordEncoding`), and the others as members of a map under `context`, which is
/// left out when the context has none of them. Each member is left out when the context has no
/// value for its key:
///
/// | Key | Member | Form |
/// |---|---|---|
/// | `SessionKey` | `session` | the UUID's uppercase string |
/// | `SampleRateKey` | `context.sampleRate` | the rate's value, a double in 0 ... 1 |
/// | `ScreenKey` | `context.screen` | the screen's name |
/// | `ApplicationKey` | `context.application` | a map of `bundleIdentifier`, `version` and `build`, each left out when `nil` |
/// | `DeviceKey` | `context.device` | a map of `model` and `formFactor` (`phone`, `pad`, `mac`, `tv`, `watch`, `vision`) |
/// | `OperatingSystemKey` | `context.operatingSystem` | a map of `name` and `version` |
/// | `LocaleKey` | `context.locale` | the locale's identifier |
/// | `NetworkKey` | `context.network` | `wifi`, `cellular`, `wiredEthernet`, `other` or `offline` |
///
/// A form factor or network name that is none of these reads back as that key absent.
///
/// No other key is kept: not `VendorIdentifierKey`, an adopter's own keys, nor a trace.
package enum StoredContext {
    /// Writes the keys of `context` a store keeps into a record map.
    ///
    /// - Parameters:
    ///   - context: The record's context.
    ///   - container: The record map.
    /// - Throws: What the container throws.
    package static func encode(_ context: ServiceContext, to container: inout KeyedEncodingContainer<RecordEncoding.Key>) throws {
        try container.encodeIfPresent(context[SessionKey.self], forKey: .session)
        let members = StoredMembers(context: context)
        if !members.isEmpty {
            try container.encode(members, forKey: .context)
        }
    }

    /// The top-level context with the keys a record map holds.
    ///
    /// - Parameter container: The record map.
    /// - Returns: The context, holding a key for each member there.
    /// - Throws: `DecodingError` when a member holds anything but the form `encode(_:to:)`
    ///   writes, null included, other than a form factor or network name no case has.
    package static func context(from container: KeyedDecodingContainer<RecordEncoding.Key>) throws -> ServiceContext {
        var context = ServiceContext.topLevel
        context[SessionKey.self] = try container.decodeWhenPresent(UUID.self, forKey: .session)
        if let members = try container.decodeWhenPresent(StoredMembers.self, forKey: .context) {
            context[SampleRateKey.self] = members.sampleRate
            context[ScreenKey.self] = members.screen
            context[ApplicationKey.self] = members.application
            context[DeviceKey.self] = members.device
            context[OperatingSystemKey.self] = members.operatingSystem
            context[LocaleKey.self] = members.locale
            context[NetworkKey.self] = members.network
        }
        return context
    }
}

extension KeyedDecodingContainer {
    /// The value of `key`, or `nil` when the map has no such member; unlike `decodeIfPresent`, a
    /// member that is null throws, as it isn't a value of `type`.
    fileprivate func decodeWhenPresent<Value: Decodable>(_ type: Value.Type, forKey key: Key) throws -> Value? {
        contains(key) ? try decode(type, forKey: key) : nil
    }
}

/// The keys under a record map's `context`, each `nil` when the context has none.
private struct StoredMembers: Codable {
    var sampleRate: SampleRate?
    var screen: String?
    var application: ApplicationKey.Value?
    var device: DeviceKey.Value?
    var operatingSystem: OperatingSystemKey.Value?
    var locale: Locale?
    var network: NetworkKey.Value?

    private enum Key: String, CodingKey {
        case sampleRate
        case screen
        case application
        case device
        case operatingSystem
        case locale
        case network
    }

    init(context: ServiceContext) {
        sampleRate = context[SampleRateKey.self]
        screen = context[ScreenKey.self]
        application = context[ApplicationKey.self]
        device = context[DeviceKey.self]
        operatingSystem = context[OperatingSystemKey.self]
        locale = context[LocaleKey.self]
        network = context[NetworkKey.self]
    }

    /// Whether the context has none of the keys.
    var isEmpty: Bool {
        sampleRate == nil && screen == nil && application == nil && device == nil && operatingSystem == nil && locale == nil && network == nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encodeIfPresent(sampleRate?.value, forKey: .sampleRate)
        try container.encodeIfPresent(screen, forKey: .screen)
        try container.encodeIfPresent(application.map(StoredApplication.init(value:)), forKey: .application)
        try container.encodeIfPresent(device.map(StoredDevice.init(value:)), forKey: .device)
        try container.encodeIfPresent(operatingSystem.map(StoredOperatingSystem.init(value:)), forKey: .operatingSystem)
        try container.encodeIfPresent(locale?.identifier, forKey: .locale)
        try container.encodeIfPresent(network?.storedName, forKey: .network)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if let rate = try container.decodeWhenPresent(Double.self, forKey: .sampleRate) {
            do {
                sampleRate = try SampleRate(rate)
            } catch {
                throw DecodingError.dataCorruptedError(forKey: .sampleRate, in: container, debugDescription: "A sample rate outside 0 ... 1.")
            }
        }
        screen = try container.decodeWhenPresent(String.self, forKey: .screen)
        application = try container.decodeWhenPresent(StoredApplication.self, forKey: .application)?.value
        device = try container.decodeWhenPresent(StoredDevice.self, forKey: .device)?.value
        operatingSystem = try container.decodeWhenPresent(StoredOperatingSystem.self, forKey: .operatingSystem)?.value
        locale = try container.decodeWhenPresent(String.self, forKey: .locale).map(Locale.init(identifier:))
        network = try container.decodeWhenPresent(String.self, forKey: .network).flatMap(NetworkKey.Value.init(storedName:))
    }
}


/// An app as a record map holds it.
private struct StoredApplication: Codable {
    let value: ApplicationKey.Value

    private enum Key: String, CodingKey {
        case bundleIdentifier
        case version
        case build
    }

    init(value: ApplicationKey.Value) {
        self.value = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encodeIfPresent(value.bundleIdentifier, forKey: .bundleIdentifier)
        try container.encodeIfPresent(value.version, forKey: .version)
        try container.encodeIfPresent(value.build, forKey: .build)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        value = ApplicationKey.Value(
            bundleIdentifier: try container.decodeWhenPresent(String.self, forKey: .bundleIdentifier),
            version: try container.decodeWhenPresent(String.self, forKey: .version),
            build: try container.decodeWhenPresent(String.self, forKey: .build)
        )
    }
}

/// A device as a record map holds it.
private struct StoredDevice: Codable {
    /// The device, or `nil` when its form factor's name is none this release knows.
    let value: DeviceKey.Value?

    private enum Key: String, CodingKey {
        case model
        case formFactor
    }

    init(value: DeviceKey.Value) {
        self.value = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encodeIfPresent(value?.model, forKey: .model)
        try container.encodeIfPresent(value?.formFactor.storedName, forKey: .formFactor)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let model = try container.decode(String.self, forKey: .model)
        let formFactor = DeviceKey.Value.FormFactor(storedName: try container.decode(String.self, forKey: .formFactor))
        value = formFactor.map { DeviceKey.Value(model: model, formFactor: $0) }
    }
}

/// An operating system as a record map holds it.
private struct StoredOperatingSystem: Codable {
    let value: OperatingSystemKey.Value

    private enum Key: String, CodingKey {
        case name
        case version
    }

    init(value: OperatingSystemKey.Value) {
        self.value = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(value.name, forKey: .name)
        try container.encode(value.version, forKey: .version)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        value = OperatingSystemKey.Value(
            name: try container.decode(String.self, forKey: .name),
            version: try container.decode(String.self, forKey: .version)
        )
    }
}

// Names written out, not the cases' descriptions, so renaming a case in Swift can't change what
// is on disk; a new case needs a name here before it compiles. A name this release doesn't know,
// as a later release's new case would be after a rollback, reads as the key absent (the whole
// device, for a form factor) and the record is kept: losing an event costs more than losing one
// attribute of its context. Rejected: keeping such a record undecodable, which would drop every
// event a later release wrote. A value that isn't text, null included, is still malformed.
extension DeviceKey.Value.FormFactor {
    /// The form factor's name in a record map.
    fileprivate var storedName: String {
        switch self {
        case .phone: "phone"
        case .pad: "pad"
        case .mac: "mac"
        case .tv: "tv"
        case .watch: "watch"
        case .vision: "vision"
        }
    }

    /// The form factor named `storedName` in a record map, or `nil` for a name of none.
    fileprivate init?(storedName: String) {
        guard let match = Self.allCases.first(where: { $0.storedName == storedName }) else { return nil }
        self = match
    }
}

extension NetworkKey.Value {
    /// The connection's name in a record map.
    fileprivate var storedName: String {
        switch self {
        case .wifi: "wifi"
        case .cellular: "cellular"
        case .wiredEthernet: "wiredEthernet"
        case .other: "other"
        case .offline: "offline"
        }
    }

    /// The connection named `storedName` in a record map, or `nil` for a name of none.
    fileprivate init?(storedName: String) {
        guard let match = Self.allCases.first(where: { $0.storedName == storedName }) else { return nil }
        self = match
    }
}
