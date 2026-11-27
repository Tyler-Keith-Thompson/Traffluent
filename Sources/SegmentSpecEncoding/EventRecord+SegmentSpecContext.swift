import Events
import Foundation
import Instrumentation
import JSONValues
import StandardContext

extension EventRecord {
    /// The Segment spec's context fields of the library's own context keys the record holds a value
    /// for (https://segment.com/docs/connections/spec/common/#context).
    ///
    /// Only what the spec has a field for, under its names. Not `app.name`, which StandardContext
    /// doesn't carry, nor `device.id`, `device.advertisingId` or `device.manufacturer`. Not the
    /// vendor identifier, the sample rate or the trace context either: the session is the only
    /// identifier sent (D4). Nor `library`: the library has no version to name in it at run time.
    var segmentSpecContext: [String: JSON] {
        var fields: [String: JSON] = [:]
        if let application = context[ApplicationKey.self] {
            let app = [
                "build": application.build.map(JSON.string),
                "namespace": application.bundleIdentifier.map(JSON.string),
                "version": application.version.map(JSON.string),
            ].compactMapValues { $0 }
            if !app.isEmpty {
                fields["app"] = .object(app)
            }
        }
        if let device = context[DeviceKey.self] {
            fields["device"] = .object(["model": .string(device.model), "type": .string(device.formFactor.segmentDeviceType)])
        }
        if let locale = context[LocaleKey.self] {
            fields["locale"] = .string(locale.identifier(.bcp47))
        }
        if let network = context[NetworkKey.self] {
            // Both members always, as Segment's Swift library sends them: the spec reads a context
            // with neither as offline.
            fields["network"] = .object(["cellular": .boolean(network == .cellular), "wifi": .boolean(network == .wifi)])
        }
        if let operatingSystem = context[OperatingSystemKey.self] {
            fields["os"] = .object(["name": .string(operatingSystem.name), "version": .string(operatingSystem.version)])
        }
        return fields
    }
}

extension DeviceKey.Value.FormFactor {
    /// The platform as Segment's Swift library (analytics-swift) writes `context.device.type`,
    /// which downstream destinations read as the platform: an iPad's is `ios` too.
    fileprivate var segmentDeviceType: String {
        switch self {
        case .phone, .pad: "ios"
        case .mac: "macos"
        case .tv: "tvos"
        case .watch: "watchos"
        case .vision: "visionos"
        }
    }
}
