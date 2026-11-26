// Checking a change to a property's sensitivity: a document never requires a Sensitive property, as
// a destination may redact it, so a sensitivity change can change what is required too.

import Events
import Testing
import TrackingPlans

@Suite("TrackingPlan: sensitivity check")
struct TrackingPlanSensitivityCheckTests {
    @Test("Making a required property Sensitive only dates the plan: the payloads that hold it still validate")
    func madeSensitive() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "String", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.outOfDate([
            .sensitivityChanged(event: "signed_up", version: 1, property: "email", isSensitive: true),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A property neither optional nor defaulted that stops being Sensitive is required now, which breaks the plan: the payloads that redacted it lack it")
    func madeRequired() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "String", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .sensitivePropertyMadeRequired(event: "signed_up", version: 1, property: "email"),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("An optional or defaulted property that stops being Sensitive only dates the plan, as it still isn't required")
    func optionalNoLongerSensitive() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: true),
            EventSchema.Property(name: "seats", typeName: "Sensitive<Int>", isOptional: false, hasDefaultValue: true),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "String", isOptional: true),
            EventSchema.Property(name: "seats", typeName: "Int", isOptional: false, hasDefaultValue: true),
        ])])
        let expected = TrackingPlanCheck.outOfDate([
            .sensitivityChanged(event: "signed_up", version: 1, property: "email", isSensitive: false),
            .sensitivityChanged(event: "signed_up", version: 1, property: "seats", isSensitive: false),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A Sensitive property neither optional nor defaulted that stops being Sensitive and is made optional only dates the plan")
    func madeOptionalAndNotSensitive() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "String", isOptional: true),
        ])])
        let expected = TrackingPlanCheck.outOfDate([
            .propertyMadeOptional(event: "signed_up", version: 1, property: "email"),
            .sensitivityChanged(event: "signed_up", version: 1, property: "email", isSensitive: false),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A Sensitive property made required and not Sensitive at once breaks the plan once, as the optionality or default it lost")
    func madeRequiredAndNotSensitive() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: true),
            EventSchema.Property(name: "seats", typeName: "Sensitive<Int>", isOptional: false, hasDefaultValue: true),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "String", isOptional: false),
            EventSchema.Property(name: "seats", typeName: "Int", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .propertyMadeRequired(event: "signed_up", version: 1, property: "email"),
            .sensitivityChanged(event: "signed_up", version: 1, property: "email", isSensitive: false),
            .defaultValueRemoved(event: "signed_up", version: 1, property: "seats"),
            .sensitivityChanged(event: "signed_up", version: 1, property: "seats", isSensitive: false),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A Sensitive type the plan can't map reads as optional, so stopping being Sensitive makes it required, and becoming Sensitive changes sensitivity alone")
    func unmappedType() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "paid", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "billing", typeName: "Coordinate", isOptional: true),
            EventSchema.Property(name: "shipping", typeName: "Sensitive<Coordinate>", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "paid", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "billing", typeName: "Sensitive<Coordinate>", isOptional: true),
            EventSchema.Property(name: "shipping", typeName: "Coordinate", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .sensitivityChanged(event: "paid", version: 1, property: "billing", isSensitive: true),
            .propertyMadeRequired(event: "paid", version: 1, property: "shipping"),
            .sensitivityChanged(event: "paid", version: 1, property: "shipping", isSensitive: false),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A deprecated Sensitive property declared again as required and not Sensitive is a required property added, once")
    func deprecatedRestored() {
        let released = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false),
        ])])
        let removed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
        ])])
        let committed = removed.files(carryingForward: released.files)
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "email", typeName: "String", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .requiredPropertyAdded(event: "signed_up", version: 1, property: "email"),
            .sensitivityChanged(event: "signed_up", version: 1, property: "email", isSensitive: false),
        ])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("An array whose elements, not Sensitive, stop allowing null is retyped, which breaks the plan")
    func elementsMadeRequired() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "codes", typeName: "[Int?]", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "codes", typeName: "[Int]", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .propertyRetyped(event: "signed_up", version: 1, property: "codes", committed: #"{"items": {"type": ["integer", "null"]}, "type": "array"}"#, current: #"{"items": {"type": "integer"}, "type": "array"}"#),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A plan exported when a Sensitive property was required and a Sensitive element couldn't be null is only out of date")
    func earlierExport() {
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false),
            EventSchema.Property(name: "recoveryCodes", typeName: "[Sensitive<String>]", isOptional: false),
            EventSchema.Property(name: "nested", typeName: "[[Sensitive<Int>]]", isOptional: false),
        ])])
        let earlierDocument = """
            {
              "$id": "signed_up.v1.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {
                "email": {"type": "string", "x-traffluent-sensitive": true},
                "nested": {"items": {"items": {"type": "integer", "x-traffluent-sensitive": true}, "type": "array"}, "type": "array"},
                "recoveryCodes": {"items": {"type": "string", "x-traffluent-sensitive": true}, "type": "array"}
              },
              "required": ["email", "recoveryCodes", "nested"],
              "title": "signed_up",
              "type": "object",
              "x-traffluent-consent-category": "analytics",
              "x-traffluent-version": 1
            }

            """
        let committed = sut.files.map { file in
            file.path == "signed_up.v1.schema.json" ? TrackingPlan.File(path: file.path, contents: Array(earlierDocument.utf8)) : file
        }
        let expected = TrackingPlanCheck.outOfDate([.fileOutOfDate(path: "signed_up.v1.schema.json")])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }
}
