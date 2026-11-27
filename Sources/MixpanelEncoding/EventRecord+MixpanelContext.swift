import Events
import Foundation
import Instrumentation
import JSONValues
import StandardContext

extension EventRecord {
    /// Mixpanel's default properties of the library's own context keys the record holds a value
    /// for, named as mixpanel-swift names them.
    ///
    /// Only what Mixpanel has a default property for. The bundle identifier, the form factor and
    /// the locale aren't sent: Mixpanel has none for them, and a property of the encoder's own
    /// could clash with one the event's schema declares. Nor is `$manufacturer`, which
    /// StandardContext doesn't carry. Not the vendor identifier, the sample rate or the trace
    /// context either: the session is the only identifier Mixpanel is sent (D4).
    var mixpanelContext: [String: JSON] {
        var properties: [String: JSON] = [:]
        if let application = context[ApplicationKey.self] {
            if let version = application.version {
                properties["$app_version_string"] = .string(version)
            }
            if let build = application.build {
                properties["$app_build_number"] = .string(build)
            }
        }
        if let device = context[DeviceKey.self] {
            properties["$model"] = .string(device.model)
        }
        if let network = context[NetworkKey.self] {
            properties["$wifi"] = .boolean(network == .wifi)
        }
        if let operatingSystem = context[OperatingSystemKey.self] {
            properties["$os"] = .string(operatingSystem.name)
            properties["$os_version"] = .string(operatingSystem.version)
        }
        return properties
    }
}
