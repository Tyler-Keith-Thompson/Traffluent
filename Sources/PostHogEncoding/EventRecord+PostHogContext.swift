import Events
import Foundation
import Instrumentation
import StandardContext
import TrackingPlans

extension EventRecord {
    /// The PostHog properties of the library's own context keys the record holds a value for.
    ///
    /// Not the vendor identifier, the sample rate or the trace context: the session is the only
    /// identifier PostHog is sent (D4), and PostHog has no property for the other two.
    var postHogContext: [String: JSON] {
        var properties: [String: JSON] = [:]
        if let application = context[ApplicationKey.self] {
            if let bundleIdentifier = application.bundleIdentifier {
                properties["$app_namespace"] = .string(bundleIdentifier)
            }
            if let version = application.version {
                properties["$app_version"] = .string(version)
            }
            if let build = application.build {
                properties["$app_build"] = .string(build)
            }
        }
        if let device = context[DeviceKey.self] {
            properties["$device_model"] = .string(device.model)
            if let deviceType = device.formFactor.postHogDeviceType {
                properties["$device_type"] = .string(deviceType)
            }
        }
        if let locale = context[LocaleKey.self] {
            properties["$locale"] = .string(locale.identifier(.bcp47))
        }
        if let network = context[NetworkKey.self] {
            properties["$network_wifi"] = .boolean(network == .wifi)
            properties["$network_cellular"] = .boolean(network == .cellular)
        }
        if let operatingSystem = context[OperatingSystemKey.self] {
            properties["$os_name"] = .string(operatingSystem.name)
            properties["$os_version"] = .string(operatingSystem.version)
        }
        return properties
    }
}

// The values posthog-ios sends as `$device_type`, so PostHog's dashboards group these events with
// its SDK's; it sends none on watchOS, so neither does this.
extension DeviceKey.Value.FormFactor {
    /// The form factor as PostHog's `$device_type`; `nil` for a watch.
    fileprivate var postHogDeviceType: String? {
        switch self {
        case .phone: "Mobile"
        case .pad: "Tablet"
        case .mac: "Desktop"
        case .tv: "TV"
        case .vision: "Vision"
        case .watch: nil
        }
    }
}
