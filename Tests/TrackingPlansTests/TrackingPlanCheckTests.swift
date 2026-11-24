// Checking a plan against a committed one: every difference, how each is classified, the report,
// and the command's check mode.

import Events
import Foundation
import Testing
import TrackingPlans

@Suite("TrackingPlan: check")
struct TrackingPlanCheckTests {
    struct CheckoutCommand: TrackingPlanCommand {
        static let trackingPlan = TrackingPlan(schemas: [
            EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
                EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
            ]),
        ])
    }

    @Test("A plan checked against its own files matches")
    func matches() {
        let sut = CheckoutCommand.trackingPlan
        let expected = TrackingPlanCheck.matches

        let actual = sut.check(against: sut.files)

        #expect(actual == expected)
        #expect(actual.differences.isEmpty)
        #expect(actual.description == "The events match the committed tracking plan.")
    }

    @Test("A renamed event is the committed one removed, which breaks, and a new one")
    func renamed() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "checkout_began", version: 2, consentCategory: .analytics, properties: [])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [])])
        let expected = TrackingPlanCheck.breaking([
            .eventRemoved(event: "checkout_began", version: 2),
            .eventAdded(event: "checkout_started", version: 2),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A removed property only dates the plan: a stored record that holds it reads with it skipped")
    func removedProperty() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
            EventSchema.Property(name: "currency", typeName: "String", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.outOfDate([.propertyRemoved(event: "checkout_started", version: 2, property: "currency")])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A retyped property breaks the plan, its schemas given on one line")
    func retyped() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "order_completed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "itemCount", typeName: "UInt16", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "order_completed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "itemCount", typeName: "[Int]", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .propertyRetyped(event: "order_completed", version: 1, property: "itemCount", committed: #"{"type": "integer"}"#, current: #"{"items": {"type": "integer"}, "type": "array"}"#),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("Retyping an optional property compares the types without the null it allows")
    func retypedOptional() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "coupon", typeName: "Int", isOptional: true),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .propertyRetyped(event: "checkout_started", version: 2, property: "coupon", committed: #"{"type": "string"}"#, current: #"{"type": "integer"}"#),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("An optional property made required breaks the plan, and is no retyping")
    func madeRequired() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "coupon", typeName: "String", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([.propertyMadeRequired(event: "checkout_started", version: 2, property: "coupon")])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A type the plan can't map made required is one difference, though its schema allows null either way")
    func unknownMadeRequired() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "visited", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "location", typeName: "Coordinate", isOptional: true),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "visited", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "location", typeName: "Coordinate", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([.propertyMadeRequired(event: "visited", version: 1, property: "location")])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("An added required property breaks the plan; an added optional one only dates it")
    func added() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [])])
        let required = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
        ])])
        let optional = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "referrer", typeName: "String", isOptional: true),
        ])])
        let expectedRequired = TrackingPlanCheck.breaking([.requiredPropertyAdded(event: "signed_up", version: 1, property: "plan")])
        let expectedOptional = TrackingPlanCheck.outOfDate([.optionalPropertyAdded(event: "signed_up", version: 1, property: "referrer")])

        let actualRequired = required.check(against: committed.files)
        let actualOptional = optional.check(against: committed.files)

        #expect(actualRequired == expectedRequired)
        #expect(actualOptional == expectedOptional)
    }

    @Test("An added property with a default value only dates the plan, though it is required")
    func addedWithDefault() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "currency", typeName: "String", isOptional: false, hasDefaultValue: true),
        ])])
        let expected = TrackingPlanCheck.outOfDate([.defaultedPropertyAdded(event: "signed_up", version: 1, property: "currency")])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A required property that loses its default value breaks the plan; one that gains a default only dates it")
    func defaultValueChanged() {
        let withoutDefault = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "currency", typeName: "String", isOptional: false),
        ])])
        let withDefault = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "currency", typeName: "String", isOptional: false, hasDefaultValue: true),
        ])])
        let expectedLost = TrackingPlanCheck.breaking([.defaultValueRemoved(event: "signed_up", version: 1, property: "currency")])
        let expectedGained = TrackingPlanCheck.outOfDate([.defaultValueAdded(event: "signed_up", version: 1, property: "currency")])

        let actualLost = withoutDefault.check(against: withDefault.files)
        let actualGained = withDefault.check(against: withoutDefault.files)

        #expect(actualLost == expectedLost)
        #expect(actualGained == expectedGained)
    }

    @Test("An optional property's default value gained or lost is no difference of meaning, only of bytes")
    func optionalDefaultValueChanged() {
        let withoutDefault = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
        ])])
        let withDefault = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "coupon", typeName: "String", isOptional: true, hasDefaultValue: true),
        ])])
        let expected = TrackingPlanCheck.outOfDate([.fileOutOfDate(path: "signed_up.v1.schema.json")])

        let actualLost = withoutDefault.check(against: withDefault.files)
        let actualGained = withDefault.check(against: withoutDefault.files)

        #expect(actualLost == expected)
        #expect(actualGained == expected)
    }

    @Test("A required property made optional, a changed consent category and a changed sensitivity only date the plan")
    func nonBreaking() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false),
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .functional, properties: [
            EventSchema.Property(name: "email", typeName: "String", isOptional: false),
            EventSchema.Property(name: "plan", typeName: "Sensitive<String>", isOptional: true),
        ])])
        let expected = TrackingPlanCheck.outOfDate([
            .consentCategoryChanged(event: "signed_up", version: 1, committed: "analytics", current: "functional"),
            .sensitivityChanged(event: "signed_up", version: 1, property: "email", isSensitive: false),
            .propertyMadeOptional(event: "signed_up", version: 1, property: "plan"),
            .sensitivityChanged(event: "signed_up", version: 1, property: "plan", isSensitive: true),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A raised version only dates the plan, and the two versions' properties aren't compared")
    func versionRaised() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 3, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "tier", typeName: "Int", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.outOfDate([.versionRaised(event: "signed_up", committed: 1, current: 3)])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A version raised past several committed ones supersedes each with the next current version")
    func versionsRaised() {
        let committed = TrackingPlan(schemas: [1, 2].map { EventSchema(name: "searched", version: $0, consentCategory: .analytics, properties: []) })
        let sut = TrackingPlan(schemas: [2, 4, 5].map { EventSchema(name: "searched", version: $0, consentCategory: .analytics, properties: []) })
        let expected = TrackingPlanCheck.outOfDate([
            .versionRaised(event: "searched", committed: 1, current: 2),
            .eventAdded(event: "searched", version: 4),
            .eventAdded(event: "searched", version: 5),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A lowered version is the committed one removed, which breaks")
    func versionLowered() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 2, consentCategory: .analytics, properties: [])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [])])
        let expected = TrackingPlanCheck.breaking([
            .eventRemoved(event: "signed_up", version: 2),
            .eventAdded(event: "signed_up", version: 1),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A new event only dates the plan")
    func eventAdded() {
        let committed = TrackingPlan(schemas: [])
        let sut = CheckoutCommand.trackingPlan
        let expected = TrackingPlanCheck.outOfDate([.eventAdded(event: "checkout_started", version: 2)])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("Differences are listed by the committed plan's events, then properties by name, then new events")
    func order() {
        let committed = TrackingPlan(schemas: ["a", "b"].map { name in
            EventSchema(name: name, version: 1, consentCategory: .analytics, properties: ["y", "x"].map {
                EventSchema.Property(name: $0, typeName: "Int", isOptional: false)
            })
        })
        let sut = TrackingPlan(schemas: ["c", "b", "a"].map { EventSchema(name: $0, version: 1, consentCategory: .analytics, properties: []) })
        let expected: [TrackingPlanDifference] = [
            .propertyRemoved(event: "a", version: 1, property: "x"),
            .propertyRemoved(event: "a", version: 1, property: "y"),
            .propertyRemoved(event: "b", version: 1, property: "x"),
            .propertyRemoved(event: "b", version: 1, property: "y"),
            .eventAdded(event: "c", version: 1),
        ]

        let actual = sut.check(against: committed.files).differences

        #expect(actual == expected)
    }

    @Test("A committed file whose bytes differ, with the same meaning, dates the plan")
    func reformatted() throws {
        let sut = CheckoutCommand.trackingPlan
        let document = try #require(sut.files.first { $0.path == "checkout_started.v2.schema.json" })
        let reformatted = TrackingPlan.File(path: document.path, contents: Array(String(decoding: document.contents, as: UTF8.self).replacingOccurrences(of: "\n", with: " ").utf8))
        let committed = sut.files.map { $0.path == document.path ? reformatted : $0 }
        let expected = TrackingPlanCheck.outOfDate([.fileOutOfDate(path: "checkout_started.v2.schema.json")])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("A missing example and a document the index doesn't list date the plan; files a plan doesn't write are ignored")
    func extraAndMissingFiles() {
        let sut = CheckoutCommand.trackingPlan
        let committed = sut.files.filter { $0.path != "checkout_started.v2.example.json" } + [
            TrackingPlan.File(path: "signed_in.v1.schema.json", contents: Array("{}\n".utf8)),
            TrackingPlan.File(path: "README.md", contents: Array("notes\n".utf8)),
        ]
        let expected = TrackingPlanCheck.outOfDate([
            .fileOutOfDate(path: "checkout_started.v2.example.json"),
            .fileOutOfDate(path: "signed_in.v1.schema.json"),
        ])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("No committed index is an unreadable index, which breaks, and the report lists only it")
    func noIndex() {
        let sut = CheckoutCommand.trackingPlan
        let expected = TrackingPlanCheck.breaking([.unreadableFile(path: "tracking-plan.json")])
        let expectedReport = """
            The events break the committed tracking plan: at the same version, a stored record or an already-released app's payload may no longer decode or validate.
              - tracking-plan.json is missing from the committed plan, or isn't a tracking plan file
            Undo each breaking change, or raise the version of each event that changed (@Event(version:)), then export the plan again: swift package --allow-writing-to-package-directory export-tracking-plan
            """

        let actual = sut.check(against: [])

        #expect(actual == expected)
        #expect(actual.description == expectedReport)
    }

    @Test("A retyping's schemas show nested arrays and objects on one line")
    func retypedNested() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "pages", typeName: "[Int]", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "pages", typeName: "[Int?]", isOptional: false),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .propertyRetyped(event: "searched", version: 1, property: "pages", committed: #"{"items": {"type": "integer"}, "type": "array"}"#, current: #"{"items": {"type": ["integer", "null"]}, "type": "array"}"#),
        ])

        let actual = sut.check(against: committed.files)

        #expect(actual == expected)
    }

    @Test("A keyword a plan doesn't write, even a null one, is part of the committed property's schema")
    func committedKeyword() throws {
        let sut = CheckoutCommand.trackingPlan
        let path = "checkout_started.v2.schema.json"
        let document = try #require(sut.files.first { $0.path == path })
        let edited = String(decoding: document.contents, as: UTF8.self).replacingOccurrences(of: #""type": "integer""#, with: #""default": null, "type": "integer""#)
        let committed = sut.files.map { $0.path == path ? TrackingPlan.File(path: path, contents: Array(edited.utf8)) : $0 }
        let expected = TrackingPlanCheck.breaking([
            .propertyRetyped(event: "checkout_started", version: 2, property: "cartSize", committed: #"{"default": null, "type": "integer"}"#, current: #"{"type": "integer"}"#),
        ])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("An index that isn't one is unreadable", arguments: ["not json", #"{"events": {}}"#, #"{"events": [{"name": "x"}]}"#, #"[]"#])
    func malformedIndex(text: String) {
        let sut = CheckoutCommand.trackingPlan
        let committed = [TrackingPlan.File(path: "tracking-plan.json", contents: Array(text.utf8))]
        let expected = TrackingPlanCheck.breaking([.unreadableFile(path: "tracking-plan.json")])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("A document the index lists that is missing or isn't one is unreadable", arguments: [
        nil, "not json", "{}",
        #"{"title": "checkout_started", "x-traffluent-version": true, "x-traffluent-consent-category": "analytics", "properties": {}, "required": []}"#,
        #"{"title": "checkout_started", "x-traffluent-version": 1.5, "x-traffluent-consent-category": "analytics", "properties": {}, "required": []}"#,
        #"{"title": "checkout_started", "x-traffluent-version": 2, "x-traffluent-consent-category": "analytics", "properties": {"a": true}, "required": []}"#,
        #"{"title": "checkout_started", "x-traffluent-version": 2, "x-traffluent-consent-category": "analytics", "properties": {}, "required": [1]}"#,
    ])
    func malformedDocument(text: String?) {
        let sut = CheckoutCommand.trackingPlan
        let path = "checkout_started.v2.schema.json"
        let committed = sut.files.filter { $0.path != path } + (text.map { [TrackingPlan.File(path: path, contents: Array($0.utf8))] } ?? [])

        let actual = sut.check(against: committed)

        #expect(actual.differences.first == .unreadableFile(path: path))
        #expect(actual.differences.first?.isBreaking == true)
    }

    @Test("A breaking check's report lists the breaking differences first, then the others, and what to do")
    func breakingReport() {
        let committed = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
        ])])
        let sut = TrackingPlan(schemas: [EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "cartSize", typeName: "String", isOptional: false),
            EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
        ])])
        let expected = """
            The events break the committed tracking plan: at the same version, a stored record or an already-released app's payload may no longer decode or validate.
              - checkout_started v2: property "cartSize" changed type from {"type": "integer"} to {"type": "string"}
            It is also out of date:
              - checkout_started v2: optional property "coupon" was added
            Undo each breaking change, or raise the version of each event that changed (@Event(version:)), then export the plan again: swift package --allow-writing-to-package-directory export-tracking-plan
            """

        let actual = sut.check(against: committed.files).description

        #expect(actual == expected)
    }

    @Test("An out-of-date check's report lists the differences and says to export again")
    func outOfDateReport() {
        let sut = CheckoutCommand.trackingPlan
        let expected = """
            The committed tracking plan is out of date:
              - checkout_started v2 is new
            Export it again: swift package --allow-writing-to-package-directory export-tracking-plan
            """

        let actual = sut.check(against: TrackingPlan(schemas: []).files).description

        #expect(actual == expected)
    }

    @Test("Each difference's line names the event and the property", arguments: [
        (TrackingPlanDifference.eventRemoved(event: "checkout_started", version: 2), "checkout_started v2 is in the committed plan, but no event named checkout_started has version 2 or later: it was renamed or removed", true),
        (.propertyRemoved(event: "e", version: 1, property: "p"), #"e v1: property "p" was removed"#, false),
        (.propertyRetyped(event: "e", version: 1, property: "p", committed: #"{"type": "integer"}"#, current: #"{"type": "string"}"#), #"e v1: property "p" changed type from {"type": "integer"} to {"type": "string"}"#, true),
        (.propertyMadeRequired(event: "e", version: 1, property: "p"), #"e v1: property "p" was optional and is now required"#, true),
        (.requiredPropertyAdded(event: "e", version: 1, property: "p"), #"e v1: required property "p" was added without a default value"#, true),
        (.defaultValueRemoved(event: "e", version: 1, property: "p"), #"e v1: property "p" lost its default value"#, true),
        (.unreadableFile(path: "tracking-plan.json"), "tracking-plan.json is missing from the committed plan, or isn't a tracking plan file", true),
        (.eventAdded(event: "e", version: 1), "e v1 is new", false),
        (.versionRaised(event: "e", committed: 1, current: 2), "e went from version 1 to 2", false),
        (.optionalPropertyAdded(event: "e", version: 1, property: "p"), #"e v1: optional property "p" was added"#, false),
        (.defaultedPropertyAdded(event: "e", version: 1, property: "p"), #"e v1: property "p" was added with a default value"#, false),
        (.defaultValueAdded(event: "e", version: 1, property: "p"), #"e v1: property "p" gained a default value"#, false),
        (.propertyMadeOptional(event: "e", version: 1, property: "p"), #"e v1: property "p" was required and is now optional"#, false),
        (.consentCategoryChanged(event: "e", version: 1, committed: "analytics", current: "functional"), "e v1: consent category changed from analytics to functional", false),
        (.sensitivityChanged(event: "e", version: 1, property: "p", isSensitive: true), #"e v1: property "p" is now sensitive"#, false),
        (.sensitivityChanged(event: "e", version: 1, property: "p", isSensitive: false), #"e v1: property "p" is no longer sensitive"#, false),
        (.fileOutOfDate(path: "e.v1.example.json"), "e.v1.example.json isn't what exporting the plan writes now", false),
    ])
    func descriptions(difference: TrackingPlanDifference, expectedDescription: String, expectedBreaking: Bool) {
        let actualDescription = difference.description
        let actualBreaking = difference.isBreaking

        #expect(actualDescription == expectedDescription)
        #expect(actualBreaking == expectedBreaking)
    }

    @Test("Checking against a directory reads the plan written there")
    func directory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sut = CheckoutCommand.trackingPlan
        try sut.write(to: directory)
        try Data("notes".utf8).write(to: directory.appendingPathComponent("README.md"))
        let expected = TrackingPlanCheck.matches

        let actual = sut.check(againstDirectory: directory)

        #expect(actual == expected)
    }

    @Test("Checking against a directory that doesn't exist finds no index")
    func noDirectory() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sut = CheckoutCommand.trackingPlan
        let expected = TrackingPlanCheck.breaking([.unreadableFile(path: "tracking-plan.json")])

        let actual = sut.check(againstDirectory: directory)

        #expect(actual == expected)
    }

    @Test("The command's check exits 0 when the committed plan matches")
    func commandMatches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try CheckoutCommand.trackingPlan.write(to: directory)
        let expected: Int32 = 0

        let actual = CheckoutCommand.run(arguments: ["check", directory.path])

        #expect(actual == expected)
    }

    // Each committed plan differs from CheckoutCommand's in one breaking way.
    static let breakingEdits: [(EventSchema, TrackingPlanDifference)] = [
        (
            EventSchema(name: "checkout_begun", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
                EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
            ]),
            .eventRemoved(event: "checkout_begun", version: 2)
        ),
        (
            EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
            ]),
            .requiredPropertyAdded(event: "checkout_started", version: 2, property: "cartSize")
        ),
        (
            EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "String", isOptional: false),
                EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
            ]),
            .propertyRetyped(event: "checkout_started", version: 2, property: "cartSize", committed: #"{"type": "string"}"#, current: #"{"type": "integer"}"#)
        ),
        (
            EventSchema(name: "checkout_started", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: true),
                EventSchema.Property(name: "coupon", typeName: "String", isOptional: true),
            ]),
            .propertyMadeRequired(event: "checkout_started", version: 2, property: "cartSize")
        ),
    ]

    @Test("The command's check exits 1 for a renamed event, a required property added, a retyped one and one made required, and the report names them", arguments: breakingEdits)
    func commandBreaking(committed: EventSchema, expectedDifference: TrackingPlanDifference) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: [committed]).write(to: directory)
        let expectedStatus: Int32 = 1
        let expectedLine = "  - \(expectedDifference)"

        let actual = CheckoutCommand.run(arguments: ["check", directory.path])
        let report = CheckoutCommand.trackingPlan.check(againstDirectory: directory).description

        #expect(actual == expectedStatus)
        #expect(report.split(separator: "\n").contains { $0 == expectedLine })
    }

    @Test("The command's check exits 2 when the committed plan is only out of date")
    func commandOutOfDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: []).write(to: directory)
        let expected: Int32 = 2

        let actual = CheckoutCommand.run(arguments: ["check", directory.path])

        #expect(actual == expected)
    }

    @Test("The command's check exits 1 when there is no committed plan")
    func commandNoPlan() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let expected: Int32 = 1

        let actual = CheckoutCommand.run(arguments: ["check", directory.path])

        #expect(actual == expected)
    }

    @Test("The command exits 64 for check alone, three arguments, or two that don't start with check", arguments: [["check"], ["check", "/dev/null/a", "/dev/null/b"], ["/dev/null/a", "/dev/null/b"]])
    func commandUsage(arguments: [String]) {
        let expected: Int32 = 64

        let actual = CheckoutCommand.run(arguments: arguments)

        #expect(actual == expected)
    }
}
