import Events
import Foundation
import Instrumentation
import JSONValues
import Sessions
import StandardContext
import Trackers

extension ServiceContext {
    /// The context a record's `context` object holds: the library's keys it has a member for, and
    /// the trace context `instrument` extracts from its `trace` member, the inverse of
    /// `EventRecord`'s `collectorContext(instrument:)`. A member of another name is left out.
    ///
    /// - Throws: ``CollectorDecodingError/malformedMember(_:)`` naming the first member, by name,
    ///   that doesn't hold what the encoder writes for it.
    init(collectorContext members: [String: JSON], instrument: any Instrument) throws(CollectorDecodingError) {
        var context = ServiceContext.topLevel
        if let application = members["application"] {
            guard let fields = application.object,
                  let bundleIdentifier = fields.optionalString("bundleIdentifier"),
                  let version = fields.optionalString("version"),
                  let build = fields.optionalString("build")
            else { throw .malformedMember("context.application") }
            context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: bundleIdentifier, version: version, build: build)
        }
        if let device = members["device"] {
            guard let fields = device.object, let model = fields["model"]?.string,
                  let formFactor = fields["formFactor"]?.string.flatMap(DeviceKey.Value.FormFactor.init(collectorName:))
            else { throw .malformedMember("context.device") }
            context[DeviceKey.self] = DeviceKey.Value(model: model, formFactor: formFactor)
        }
        if let locale = members["locale"] {
            guard let identifier = locale.string else { throw .malformedMember("context.locale") }
            context[LocaleKey.self] = Locale(identifier: identifier)
        }
        if let network = members["network"] {
            guard let value = network.string.flatMap(NetworkKey.Value.init(collectorName:)) else { throw .malformedMember("context.network") }
            context[NetworkKey.self] = value
        }
        if let operatingSystem = members["operatingSystem"] {
            guard let fields = operatingSystem.object, let name = fields["name"]?.string, let version = fields["version"]?.string else {
                throw .malformedMember("context.operatingSystem")
            }
            context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: name, version: version)
        }
        if let sampleRate = members["sampleRate"] {
            guard let value = sampleRate.double, let rate = try? SampleRate(value) else { throw .malformedMember("context.sampleRate") }
            context[SampleRateKey.self] = rate
        }
        if let session = members["session"] {
            guard let key = session.string.flatMap(UUID.init(uuidString:)) else { throw .malformedMember("context.session") }
            context[SessionKey.self] = key
        }
        if let trace = members["trace"] {
            guard let entries = trace.object else { throw .malformedMember("context.trace") }
            var fields: [String: String] = [:]
            for (key, value) in entries {
                guard let text = value.string else { throw .malformedMember("context.trace") }
                fields[key] = text
            }
            instrument.extract(fields, into: &context, using: DictionaryExtractor())
        }
        if let vendorIdentifier = members["vendorIdentifier"] {
            guard let identifier = vendorIdentifier.string.flatMap(UUID.init(uuidString:)) else {
                throw .malformedMember("context.vendorIdentifier")
            }
            context[VendorIdentifierKey.self] = Sensitive(identifier)
        }
        self = context
    }
}

extension [String: JSON] {
    /// The text of the member `key`: `.some(nil)` when there is none, and `nil` when it holds
    /// anything but a string.
    fileprivate func optionalString(_ key: String) -> String?? {
        guard let value = self[key] else { return .some(nil) }
        return value.string.map(Optional.some)
    }
}

extension DeviceKey.Value.FormFactor {
    /// The form factor the collector names `name`, by the encoder's own names.
    fileprivate init?(collectorName name: String) {
        guard let formFactor = Self.allCases.first(where: { $0.collectorName == name }) else { return nil }
        self = formFactor
    }
}

extension NetworkKey.Value {
    /// The network the collector names `name`, by the encoder's own names.
    fileprivate init?(collectorName name: String) {
        guard let network = Self.allCases.first(where: { $0.collectorName == name }) else { return nil }
        self = network
    }
}

/// Reads the values an instrument extracts from a dictionary, one entry per key.
private struct DictionaryExtractor: Extractor {
    func extract(key: String, from carrier: [String: String]) -> String? {
        carrier[key]
    }
}
