import Events
import Foundation
import Instrumentation
import JSONValues
import StandardContext

extension EventRecord {
    /// Amplitude's top-level fields of the library's own context keys the record holds a value
    /// for.
    ///
    /// Only what Amplitude has a field for. The bundle identifier, the build, the form factor and
    /// the network aren't sent: Amplitude has no field for them, and writing them into
    /// `event_properties` would give every event properties its schema doesn't declare, which
    /// could clash with one it does. Not the vendor identifier, the sample rate or the trace
    /// context either: the session is the only identifier Amplitude is sent (D4).
    var amplitudeContext: [String: JSON] {
        var fields: [String: JSON] = [:]
        if let version = context[ApplicationKey.self]?.version {
            fields["app_version"] = .string(version)
        }
        if let device = context[DeviceKey.self] {
            fields["device_model"] = .string(device.model)
        }
        if let locale = context[LocaleKey.self] {
            // Amplitude reads a language tag and stores the language's name (`en-US` as English).
            fields["language"] = .string(locale.identifier(.bcp47))
        }
        if let operatingSystem = context[OperatingSystemKey.self] {
            // The system is the platform as well: StandardContext has nothing else that names one.
            fields["platform"] = .string(operatingSystem.name)
            fields["os_name"] = .string(operatingSystem.name)
            fields["os_version"] = .string(operatingSystem.version)
        }
        return fields
    }
}
