import Events
import Foundation
import Instrumentation
import JSONValues
import StandardContext

// The keys and their forms are TelemetryDeck's default parameters
// (https://telemetrydeck.com/docs/ingest/default-parameters/, read on 2026-11-27), written as its
// SwiftSDK writes them (DefaultSignalPayload in 2.14.2): `versionAndBuildNumber` is
// "<version> (build <build>)", each system version is prefixed with the platform ("iOS 26.1.0",
// "iOS 26", "iOS 26.1"), the locale is Locale's identifier ("en_US"), the language its language
// code and the region its region's.
extension EventRecord {
    /// TelemetryDeck's built-in parameters for the library's own context keys the record holds a
    /// value for.
    ///
    /// Only what TelemetryDeck has a parameter for. The bundle identifier, the form factor and the
    /// network aren't sent: TelemetryDeck has no parameter for them, and one of the encoder's own
    /// would be a dimension no insight reads. Not the vendor identifier, the sample rate or the
    /// trace context either: the session is the only identifier TelemetryDeck is sent (D4).
    var telemetryDeckContext: [String: JSON] {
        var parameters: [String: JSON] = [:]
        if let application = context[ApplicationKey.self] {
            if let version = application.version {
                parameters["TelemetryDeck.AppInfo.version"] = .string(version)
            }
            if let build = application.build {
                parameters["TelemetryDeck.AppInfo.buildNumber"] = .string(build)
            }
            if let version = application.version, let build = application.build {
                parameters["TelemetryDeck.AppInfo.versionAndBuildNumber"] = .string("\(version) (build \(build))")
            }
        }
        if let device = context[DeviceKey.self] {
            parameters["TelemetryDeck.Device.modelName"] = .string(device.model)
        }
        if let operatingSystem = context[OperatingSystemKey.self] {
            // The system is the platform as well: StandardContext tells no Mac Catalyst app or
            // iPad app on a Mac from a Mac app, which the SDK's platform does.
            parameters["TelemetryDeck.Device.operatingSystem"] = .string(operatingSystem.name)
            parameters["TelemetryDeck.Device.platform"] = .string(operatingSystem.name)
            if !operatingSystem.version.isEmpty {
                let components = operatingSystem.version.split(separator: ".", omittingEmptySubsequences: false)
                parameters["TelemetryDeck.Device.systemVersion"] = .string("\(operatingSystem.name) \(operatingSystem.version)")
                parameters["TelemetryDeck.Device.systemMajorVersion"] = .string("\(operatingSystem.name) \(components.prefix(1).joined())")
                parameters["TelemetryDeck.Device.systemMajorMinorVersion"] = .string("\(operatingSystem.name) \(components.prefix(2).joined(separator: "."))")
            }
        }
        if let locale = context[LocaleKey.self] {
            parameters["TelemetryDeck.RunContext.locale"] = .string(locale.identifier)
            if let language = locale.language.languageCode {
                parameters["TelemetryDeck.RunContext.language"] = .string(language.identifier)
            }
            if let region = locale.region {
                parameters["TelemetryDeck.UserPreference.region"] = .string(region.identifier)
            }
        }
        return parameters
    }
}
