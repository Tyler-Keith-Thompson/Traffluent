public import Events
import Foundation
public import JSONValues
import StandardContext

extension EventRecord {
    /// The standard context the record holds, as JSON members, for a vendor to rename or flatten
    /// (`flattened(separator:)`).
    ///
    /// | Member | Key | Holds |
    /// |---|---|---|
    /// | `application` | `ApplicationKey` | `bundleIdentifier`, `version` and `build`, each left out when `nil` |
    /// | `device` | `DeviceKey` | `model`, and `formFactor`: `phone`, `pad`, `mac`, `tv`, `watch` or `vision` |
    /// | `locale` | `LocaleKey` | The locale's BCP 47 identifier, such as `en-US` |
    /// | `network` | `NetworkKey` | `wifi`, `cellular`, `wiredEthernet`, `other` or `offline` |
    /// | `operatingSystem` | `OperatingSystemKey` | `name` and `version` |
    ///
    /// A key the context has no value for has no member. Neither the session nor the vendor
    /// identifier is here: the identity a vendor is sent is ``pseudonymousIdentity`` (D4).
    public var standardContext: [String: JSON] {
        var members: [String: JSON] = [:]
        if let application = context[ApplicationKey.self] {
            members["application"] = .object([
                "bundleIdentifier": application.bundleIdentifier.map(JSON.string),
                "version": application.version.map(JSON.string),
                "build": application.build.map(JSON.string),
            ].compactMapValues { $0 })
        }
        if let device = context[DeviceKey.self] {
            members["device"] = .object(["model": .string(device.model), "formFactor": .string(device.formFactor.name)])
        }
        if let locale = context[LocaleKey.self] {
            members["locale"] = .string(locale.identifier(.bcp47))
        }
        if let network = context[NetworkKey.self] {
            members["network"] = .string(network.name)
        }
        if let operatingSystem = context[OperatingSystemKey.self] {
            members["operatingSystem"] = .object(["name": .string(operatingSystem.name), "version": .string(operatingSystem.version)])
        }
        return members
    }
}

// Spelled out rather than `String(describing:)`, so renaming a case can't change what is sent.
// CollectorEncoding writes the same names for its own wire format, written again there rather
// than shared, as either may change alone.
extension DeviceKey.Value.FormFactor {
    fileprivate var name: String {
        switch self {
        case .phone: "phone"
        case .pad: "pad"
        case .mac: "mac"
        case .tv: "tv"
        case .watch: "watch"
        case .vision: "vision"
        }
    }
}

extension NetworkKey.Value {
    fileprivate var name: String {
        switch self {
        case .wifi: "wifi"
        case .cellular: "cellular"
        case .wiredEthernet: "wiredEthernet"
        case .other: "other"
        case .offline: "offline"
        }
    }
}
