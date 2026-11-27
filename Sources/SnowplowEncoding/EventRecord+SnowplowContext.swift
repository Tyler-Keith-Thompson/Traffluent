import Events
import Foundation
import JSONValues
import StandardContext

// The entities' schemas, from Iglu Central (read on 2026-11-27):
// - iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3: osType, osVersion,
//   deviceManufacturer and deviceModel required, no other member allowed; language at most 8
//   characters; networkType mobile, wifi or offline. It also holds appleIdfa, appleIdfv,
//   androidIdfa and openIdfa, which are never sent (D4).
// - iglu:com.snowplowanalytics.mobile/application/jsonschema/1-0-0: version and build, both
//   required, each at most 255 characters.
// The values follow Snowplow's iOS tracker (snowplow-ios-tracker 6.5.0, DeviceInfoMonitor and
// Utilities): osType ios, tvos, watchos, visionos or osx; deviceManufacturer "Apple Inc."; and the
// platform mob for iOS, iPadOS, watchOS and visionOS, tv for tvOS, and pc for macOS.

extension EventRecord {
    /// The Snowplow platform the record was tracked on, from its device's form factor: `mob` for
    /// a phone, pad, watch or Vision Pro, `tv` for an Apple TV, `pc` for a Mac, and `app`, a
    /// general application, when its context has no device.
    var snowplowPlatform: String {
        guard let device = context[DeviceKey.self] else { return "app" }
        switch device.formFactor {
        // visionOS too, as Snowplow's iOS tracker sends it, since `headset` needs Enrich 4.
        case .phone, .pad, .watch, .vision: return "mob"
        case .tv: return "tv"
        case .mac: return "pc"
        }
    }

    /// The Snowplow entities the record's standard context makes, as self-describing JSON: its
    /// device's `mobile_context` when the context has both a device and an operating system, and
    /// its app's `application` when the app has both a version and a build of at most 255 UTF-16
    /// code units.
    var snowplowEntities: [JSON] {
        var entities: [JSON] = []
        if let device = context[DeviceKey.self], let operatingSystem = context[OperatingSystemKey.self] {
            var mobile: [String: JSON] = [
                "osType": .string(operatingSystem.snowplowOSType),
                "osVersion": .string(operatingSystem.version),
                "deviceManufacturer": .string("Apple Inc."),
                "deviceModel": .string(device.model),
            ]
            if let networkType = context[NetworkKey.self]?.snowplowNetworkType {
                mobile["networkType"] = .string(networkType)
            }
            // ISO 639, at most 8 characters, as the schema takes: the language code alone.
            if let language = context[LocaleKey.self]?.language.languageCode?.identifier, language.utf16.count <= 8 {
                mobile["language"] = .string(language)
            }
            entities.append(.selfDescribing("iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3", data: .object(mobile)))
        }
        // Both or neither, as the schema requires both, and a value over its 255 characters
        // fails the whole event.
        if let application = context[ApplicationKey.self], let version = application.version, let build = application.build,
           version.utf16.count <= 255, build.utf16.count <= 255 {
            entities.append(.selfDescribing("iglu:com.snowplowanalytics.mobile/application/jsonschema/1-0-0", data: .object(["version": .string(version), "build": .string(build)])))
        }
        return entities
    }
}

extension JSON {
    /// A self-describing JSON value: `data`, and the Iglu URI of its schema.
    static func selfDescribing(_ schema: String, data: JSON) -> JSON {
        .object(["schema": .string(schema), "data": data])
    }
}

extension OperatingSystemKey.Value {
    /// The operating system as `mobile_context`'s `osType` names it: Snowplow's iOS tracker's
    /// names for Apple's systems, and any other name in lowercase.
    fileprivate var snowplowOSType: String {
        switch name {
        case "iOS": "ios"
        case "tvOS": "tvos"
        case "watchOS": "watchos"
        case "visionOS": "visionos"
        case "macOS": "osx"
        default: name.lowercased()
        }
    }
}

extension NetworkKey.Value {
    /// The connection as `mobile_context`'s `networkType` names it, or `nil` for a wired or other
    /// connection, which it has no value for.
    fileprivate var snowplowNetworkType: String? {
        switch self {
        case .wifi: "wifi"
        case .cellular: "mobile"
        case .offline: "offline"
        case .wiredEthernet, .other: nil
        }
    }
}
