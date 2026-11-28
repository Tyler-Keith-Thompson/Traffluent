// A fixture app's events, exported as a plan and pinned byte for byte, with the plan's rules.

import EventMacros
import Foundation
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("TrackingPlan")
private struct TrackingPlanTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
        var coupon: String?
    }

    @Event(name: "order_completed")
    struct OrderCompleted {
        var orderID: UUID
        var total: Double
        var itemCount: UInt16
        var items: [String]
        var completedAt: Date
        var express: Bool
    }

    @Event(name: "cart_viewed", version: 3)
    struct CartViewed {
        var currency: String = "USD"
        var coupon: String? = "WELCOME"
    }

    @Event(name: "signed_up", consent: .functional)
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
    }

    @Test("A plan's files are its index, then each event's document and example, ordered by name")
    func paths() throws {
        let expected = [
            "tracking-plan.json",
            "checkout_started.v2.schema.json", "checkout_started.v2.example.json",
            "order_completed.v1.schema.json", "order_completed.v1.example.json",
            "signed_up.v1.schema.json", "signed_up.v1.example.json",
        ]
        let sut = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema, OrderCompleted.schema])

        let actual = sut.files.map(\.path)

        #expect(actual == expected)
    }

    @Test("The index lists every event's name, version, consent category, document and example")
    func index() throws {
        let expected = """
            {
              "events": [
                {
                  "consentCategory": "analytics",
                  "example": "checkout_started.v2.example.json",
                  "name": "checkout_started",
                  "schema": "checkout_started.v2.schema.json",
                  "version": 2
                },
                {
                  "consentCategory": "analytics",
                  "example": "order_completed.v1.example.json",
                  "name": "order_completed",
                  "schema": "order_completed.v1.schema.json",
                  "version": 1
                },
                {
                  "consentCategory": "functional",
                  "example": "signed_up.v1.example.json",
                  "name": "signed_up",
                  "schema": "signed_up.v1.schema.json",
                  "version": 1
                }
              ]
            }

            """
        let sut = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema, OrderCompleted.schema])

        let actual = try #require(sut.files.first { $0.path == "tracking-plan.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An event's document requires its non-optional properties and lets an optional one be null")
    func checkoutStarted() throws {
        let expected = """
            {
              "$id": "checkout_started.v2.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {
                "cartSize": {
                  "type": "integer"
                },
                "coupon": {
                  "type": [
                    "string",
                    "null"
                  ]
                }
              },
              "required": [
                "cartSize"
              ],
              "title": "checkout_started",
              "type": "object",
              "x-traffluent-consent-category": "analytics",
              "x-traffluent-version": 2
            }

            """
        let sut = try TrackingPlan(schemas: [CheckoutStarted.schema])

        let actual = try #require(sut.files.first { $0.path == "checkout_started.v2.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An event's document maps UUID, Double, a bounded integer, an array, Date and Bool, and lists required properties in declaration order")
    func orderCompleted() throws {
        let expected = """
            {
              "$id": "order_completed.v1.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {
                "completedAt": {
                  "format": "date-time",
                  "type": "string"
                },
                "express": {
                  "type": "boolean"
                },
                "itemCount": {
                  "maximum": 65535,
                  "minimum": 0,
                  "type": "integer"
                },
                "items": {
                  "items": {
                    "type": "string"
                  },
                  "type": "array"
                },
                "orderID": {
                  "format": "uuid",
                  "type": "string"
                },
                "total": {
                  "type": "number"
                }
              },
              "required": [
                "orderID",
                "total",
                "itemCount",
                "items",
                "completedAt",
                "express"
              ],
              "title": "order_completed",
              "type": "object",
              "x-traffluent-consent-category": "analytics",
              "x-traffluent-version": 1
            }

            """
        let sut = try TrackingPlan(schemas: [OrderCompleted.schema])

        let actual = try #require(sut.files.first { $0.path == "order_completed.v1.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An event's document marks a Sensitive property, which it doesn't require, and names the event's consent category")
    func signedUp() throws {
        let expected = """
            {
              "$id": "signed_up.v1.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {
                "email": {
                  "type": "string",
                  "x-traffluent-sensitive": true
                },
                "plan": {
                  "type": "string"
                },
                "referrer": {
                  "type": [
                    "string",
                    "null"
                  ]
                }
              },
              "required": [
                "plan"
              ],
              "title": "signed_up",
              "type": "object",
              "x-traffluent-consent-category": "functional",
              "x-traffluent-version": 1
            }

            """
        let sut = try TrackingPlan(schemas: [SignedUp.schema])

        let actual = try #require(sut.files.first { $0.path == "signed_up.v1.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("The same schemas in any order make the same bytes, every time")
    func deterministic() throws {
        let first = try TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema, OrderCompleted.schema])
        let second = try TrackingPlan(schemas: [OrderCompleted.schema, SignedUp.schema, CheckoutStarted.schema])

        let expected = first.files
        let actual = second.files

        #expect(actual == expected)
        #expect(first.files == expected)
    }

    @Test("A plan with no events has an index with no events and no documents")
    func empty() throws {
        let expectedPaths = ["tracking-plan.json"]
        let expectedIndex = "{\n  \"events\": []\n}\n"
        let sut = try TrackingPlan(schemas: [])

        let actual = sut.files

        #expect(actual.map(\.path) == expectedPaths)
        #expect(actual.map { String(decoding: $0.contents, as: UTF8.self) } == [expectedIndex])
    }

    @Test("An event's document marks each property with a default value and requires none of them, as a payload from before one was added lacks it; its version is the macro's")
    func defaultValues() throws {
        let expected = """
            {
              "$id": "cart_viewed.v3.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {
                "coupon": {
                  "type": [
                    "string",
                    "null"
                  ],
                  "x-traffluent-default": true
                },
                "currency": {
                  "type": "string",
                  "x-traffluent-default": true
                }
              },
              "required": [],
              "title": "cart_viewed",
              "type": "object",
              "x-traffluent-consent-category": "analytics",
              "x-traffluent-version": 3
            }

            """
        let sut = try TrackingPlan(schemas: [CartViewed.schema])

        let actual = try #require(sut.files.first { $0.path == "cart_viewed.v3.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An event with no properties has empty properties and requires nothing")
    func noProperties() throws {
        let expected = """
            {
              "$id": "app_opened.v1.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {},
              "required": [],
              "title": "app_opened",
              "type": "object",
              "x-traffluent-consent-category": "analytics",
              "x-traffluent-version": 1
            }

            """
        let sut = try TrackingPlan(schemas: [EventSchema(name: "app_opened", version: 1, consentCategory: .analytics, properties: [])])

        let actual = try #require(sut.files.last { $0.path.hasSuffix(".schema.json") })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("Two versions of one event are two documents, the lower version first")
    func versions() throws {
        let expected = ["tracking-plan.json", "searched.v1.schema.json", "searched.v2.schema.json", "searched.v10.schema.json"]
        let sut = try TrackingPlan(schemas: [
            EventSchema(name: "searched", version: 2, consentCategory: .analytics, properties: []),
            EventSchema(name: "searched", version: 10, consentCategory: .analytics, properties: []),
            EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: []),
        ])

        let actual = sut.files.map(\.path).filter { $0.hasSuffix(".schema.json") || $0 == "tracking-plan.json" }

        #expect(actual == expected)
    }

    @Test("A plan's schemas of one event are ordered by version, the lower first")
    func schemasByVersion() throws {
        let expected = [1, 2, 10]
        let sut = try TrackingPlan(schemas: [2, 10, 1].map { EventSchema(name: "searched", version: $0, consentCategory: .analytics, properties: []) })

        let actual = sut.schemas.map(\.version)

        #expect(actual == expected)
    }

    @Test("Schemas are ordered by their names' UTF-8 bytes, so uppercase comes before lowercase")
    func byteOrder() throws {
        let expected = ["Zulu", "apple", "zebra", "é"]
        let sut = try TrackingPlan(schemas: ["é", "zebra", "Zulu", "apple"].map {
            EventSchema(name: $0, version: 1, consentCategory: .analytics, properties: [])
        })

        let actual = sut.schemas.map(\.name)

        #expect(actual == expected)
    }

    @Test("A name's bytes other than ASCII letters, digits, _ and - are percent-encoded in its file names")
    func fileNames() throws {
        let expected = [
            "tracking-plan.json",
            "Box%3CString%3E.v1.schema.json", "Box%3CString%3E.v1.example.json",
            "a%2Fb%20c.v1.schema.json", "a%2Fb%20c.v1.example.json",
            "caf%C3%A9.v1.schema.json", "caf%C3%A9.v1.example.json",
            "ok_name-1.v1.schema.json", "ok_name-1.v1.example.json",
            "tab%09.v1.schema.json", "tab%09.v1.example.json",
        ]
        let sut = try TrackingPlan(schemas: ["Box<String>", "a/b c", "café", "ok_name-1", "tab\t"].map {
            EventSchema(name: $0, version: 1, consentCategory: .analytics, properties: [])
        })

        let actual = sut.files.map(\.path)

        #expect(actual == expected)
    }

    @Test("Quotes, backslashes and control characters in a name are escaped, and other characters kept")
    func escaping() throws {
        let expectedTitle = #"  "title": "say \"hi\" \\ to\n\r\t\b\f\u0001\u001Fé","#
        let sut = try TrackingPlan(schemas: [EventSchema(name: "say \"hi\" \\ to\n\r\t\u{08}\u{0C}\u{01}\u{1F}é", version: 1, consentCategory: .analytics, properties: [])])

        let actual = try #require(sut.files.last { $0.path.hasSuffix(".schema.json") })

        #expect(String(decoding: actual.contents, as: UTF8.self).split(separator: "\n").contains { $0 == expectedTitle })
    }

    @Test("The initializer throws emptyEventName for a schema with no name")
    func emptyName() {
        let schemas = [EventSchema(name: "", version: 1, consentCategory: .analytics, properties: [])]

        #expect(throws: TrackingPlanError.emptyEventName) {
            try TrackingPlan(schemas: schemas)
        }
    }

    @Test("The initializer throws duplicateProperty for a schema listing a property twice")
    func duplicateProperty() {
        let property = EventSchema.Property(name: "plan", typeName: "String", isOptional: false)
        let schemas = [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [property, property])]

        #expect(throws: TrackingPlanError.duplicateProperty) {
            try TrackingPlan(schemas: schemas)
        }
    }

    @Test("The initializer throws duplicateEvent for two schemas of one name and version, naming them and no types")
    func duplicateEvent() {
        let schemas = [
            EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: []),
            EventSchema(name: "signed_up", version: 1, consentCategory: .advertising, properties: []),
        ]
        let expected = TrackingPlanError.duplicateEvent("signed_up", version: 1, firstType: nil, secondType: nil)

        #expect(throws: expected) {
            try TrackingPlan(schemas: schemas)
        }
    }

    @Test("The initializer throws duplicateEvent for names that differ only in case, even with names between them")
    func caseOnly() {
        let schemas = ["SignedUp", "Search", "signedUp"].map {
            EventSchema(name: $0, version: 1, consentCategory: .analytics, properties: [])
        }
        let expected = TrackingPlanError.duplicateEvent("signedUp", version: 1, firstType: nil, secondType: nil)

        #expect(throws: expected) {
            try TrackingPlan(schemas: schemas)
        }
    }

    @Test("The initializer throws invalidKeyword for a keyword no constraint could state", arguments: [
        ValidationKeyword.minLength(-1), .maxLength(-1), .minItems(-1), .maxItems(-1),
        .minimum(.nan), .maximum(.infinity), .minimum(-.infinity),
        .pattern("(", example: "("), .pattern("^[0-9]+$", example: "abc"),
    ])
    func invalidKeyword(_ keyword: ValidationKeyword) {
        let property = EventSchema.Property(name: "plan", typeName: "String", isOptional: false, keywords: [keyword])
        let schemas = [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [property])]

        #expect(throws: TrackingPlanError.invalidKeyword) {
            try TrackingPlan(schemas: schemas)
        }
    }

    @Test("The initializer throws invalidKeyword for a property whose Refined type's rule throws, optional or not, rather than export it as unconstrained")
    func invalidRefinedRule() {
        enum Broken: Refinement {
            static var constraints: [Constraint<String>] {
                get throws(InvalidConstraint) { try [.maxLength(-1)] }
            }
        }
        let optional = EventSchema.Property(
            name: "plan", typeName: "Refined<String, Broken>", isOptional: true,
            hasInvalidConstraint: ValidationKeyword.hasInvalidConstraint(of: \Optional<Refined<String, Broken>>.self),
            keywords: ValidationKeyword.keywords(of: Optional<Refined<String, Broken>>.self)
        )
        let schemas = [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [optional])]

        #expect(optional.hasInvalidConstraint)
        #expect(throws: TrackingPlanError.invalidKeyword) {
            try TrackingPlan(schemas: schemas)
        }
    }

    @Test("The initializer accepts the boundary keywords: counts of 0, finite bounds, a pattern its example matches")
    func boundaryKeywords() throws {
        let expected: [ValidationKeyword] = [.minLength(0), .maxItems(0), .minimum(-.greatestFiniteMagnitude), .maximum(.greatestFiniteMagnitude), .pattern("^[0-9]+$", example: "12")]
        let property = EventSchema.Property(name: "plan", typeName: "String", isOptional: false, keywords: expected)

        let actual = try TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [property])])

        #expect(actual.schemas.first?.properties.first?.keywords == expected)
    }

    @Test("The initializer makes a plan of valid schemas, ordered by name")
    func valid() throws {
        let schemas = [SignedUp.schema, CheckoutStarted.schema]
        let expected = [CheckoutStarted.schema, SignedUp.schema]

        let actual = try TrackingPlan(schemas: schemas)

        #expect(actual.schemas == expected)
    }
}
