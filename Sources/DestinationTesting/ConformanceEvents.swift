import Events

// Hand-written rather than with @Event, as the library's own events are, so the kit builds no
// swift-syntax: a vendor package's tests that only run the kit don't pay for the macro.

/// An event of each consent category the checks need, with a label to find it by in a body.
struct ConformanceAnalyticsEvent: Event, Codable {
    static let name = "traffluent_conformance_analytics"
    static let consentCategory = ConsentCategory.analytics
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [
        EventSchema.Property(name: "label", typeName: "String", isOptional: false),
    ])

    var label: String
}

/// An event the tracker's consent grants but the destination doesn't accept.
struct ConformanceFunctionalEvent: Event, Codable {
    static let name = "traffluent_conformance_functional"
    static let consentCategory = ConsentCategory.functional
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [
        EventSchema.Property(name: "label", typeName: "String", isOptional: false),
    ])

    var label: String
}

/// An event of a category the tracker's consent denies.
struct ConformanceAdvertisingEvent: Event, Codable {
    static let name = "traffluent_conformance_advertising"
    static let consentCategory = ConsentCategory.advertising
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [
        EventSchema.Property(name: "label", typeName: "String", isOptional: false),
    ])

    var label: String
}

/// An event holding a `Sensitive` value.
struct ConformanceSensitiveEvent: Event, Codable {
    static let name = "traffluent_conformance_sensitive"
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [
        EventSchema.Property(name: "label", typeName: "String", isOptional: false),
        EventSchema.Property(name: "secret", typeName: "Sensitive<String>", isOptional: false),
    ])

    var label: String
    var secret: Sensitive<String>
}
