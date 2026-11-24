import Events
import Foundation
import Instrumentation
import Sessions
import StandardContext
import TrackingPlans
import Trackers

extension EventRecord {
    /// The members of the record's `context` object: the library's own keys it holds a value for,
    /// and the trace context `instrument` injects.
    func collectorContext(instrument: any Instrument) -> [String: JSON] {
        var members: [String: JSON] = [:]
        if let application = context[ApplicationKey.self] {
            members["application"] = .object([
                "bundleIdentifier": application.bundleIdentifier.map(JSON.string),
                "version": application.version.map(JSON.string),
                "build": application.build.map(JSON.string),
            ].compactMapValues { $0 })
        }
        if let device = context[DeviceKey.self] {
            members["device"] = .object(["model": .string(device.model), "formFactor": .string(device.formFactor.collectorName)])
        }
        if let locale = context[LocaleKey.self] {
            members["locale"] = .string(locale.identifier(.bcp47))
        }
        if let network = context[NetworkKey.self] {
            members["network"] = .string(network.collectorName)
        }
        if let operatingSystem = context[OperatingSystemKey.self] {
            members["operatingSystem"] = .object(["name": .string(operatingSystem.name), "version": .string(operatingSystem.version)])
        }
        if let sampleRate = context[SampleRateKey.self] {
            members["sampleRate"] = .number(exactly: sampleRate.value)
        }
        if let session = context[SessionKey.self] {
            members["session"] = .string(session.uuidString)
        }
        if let vendorIdentifier = context[VendorIdentifierKey.self].flatMap(reveal) {
            members["vendorIdentifier"] = .string(vendorIdentifier.uuidString)
        }
        var trace: [String: String] = [:]
        instrument.inject(context, into: &trace, using: DictionaryInjector())
        if !trace.isEmpty {
            members["trace"] = .object(trace.mapValues(JSON.string))
        }
        return members
    }
}

// Spelled out rather than `String(describing:)`, so renaming a case can't change what is sent.
extension DeviceKey.Value.FormFactor {
    fileprivate var collectorName: String {
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
    fileprivate var collectorName: String {
        switch self {
        case .wifi: "wifi"
        case .cellular: "cellular"
        case .wiredEthernet: "wiredEthernet"
        case .other: "other"
        case .offline: "offline"
        }
    }
}

/// Writes the values an instrument injects into a dictionary, one entry per key.
private struct DictionaryInjector: Injector {
    func inject(_ value: String, forKey key: String, into carrier: inout [String: String]) {
        carrier[key] = value
    }
}
