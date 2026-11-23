// A fixture app's events, exported as a plan and pinned byte for byte, with the plan's rules.

import EventMacros
import Foundation
import Testing
import TrackingPlans

@Suite("TrackingPlan")
struct TrackingPlanTests {
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

    @Event(name: "signed_up", consent: .functional)
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
    }

    @Test("A plan's files are its index, then each event's document and example, ordered by name")
    func paths() {
        let expected = [
            "tracking-plan.json",
            "checkout_started.v2.schema.json", "checkout_started.v2.example.json",
            "order_completed.v1.schema.json", "order_completed.v1.example.json",
            "signed_up.v1.schema.json", "signed_up.v1.example.json",
        ]
        let sut = TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema, OrderCompleted.schema])

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
        let sut = TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema, OrderCompleted.schema])

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
        let sut = TrackingPlan(schemas: [CheckoutStarted.schema])

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
        let sut = TrackingPlan(schemas: [OrderCompleted.schema])

        let actual = try #require(sut.files.first { $0.path == "order_completed.v1.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An event's document marks a Sensitive property and names the event's consent category")
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
                "plan",
                "email"
              ],
              "title": "signed_up",
              "type": "object",
              "x-traffluent-consent-category": "functional",
              "x-traffluent-version": 1
            }

            """
        let sut = TrackingPlan(schemas: [SignedUp.schema])

        let actual = try #require(sut.files.first { $0.path == "signed_up.v1.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("The same schemas in any order make the same bytes, every time")
    func deterministic() {
        let first = TrackingPlan(schemas: [SignedUp.schema, CheckoutStarted.schema, OrderCompleted.schema])
        let second = TrackingPlan(schemas: [OrderCompleted.schema, SignedUp.schema, CheckoutStarted.schema])

        let expected = first.files
        let actual = second.files

        #expect(actual == expected)
        #expect(first.files == expected)
    }

    @Test("A plan with no events has an index with no events and no documents")
    func empty() {
        let expectedPaths = ["tracking-plan.json"]
        let expectedIndex = "{\n  \"events\": []\n}\n"
        let sut = TrackingPlan(schemas: [])

        let actual = sut.files

        #expect(actual.map(\.path) == expectedPaths)
        #expect(actual.map { String(decoding: $0.contents, as: UTF8.self) } == [expectedIndex])
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
        let sut = TrackingPlan(schemas: [EventSchema(name: "app_opened", version: 1, consentCategory: .analytics, properties: [])])

        let actual = try #require(sut.files.last { $0.path.hasSuffix(".schema.json") })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("Two versions of one event are two documents, the lower version first")
    func versions() {
        let expected = ["tracking-plan.json", "searched.v1.schema.json", "searched.v2.schema.json", "searched.v10.schema.json"]
        let sut = TrackingPlan(schemas: [
            EventSchema(name: "searched", version: 2, consentCategory: .analytics, properties: []),
            EventSchema(name: "searched", version: 10, consentCategory: .analytics, properties: []),
            EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: []),
        ])

        let actual = sut.files.map(\.path).filter { $0.hasSuffix(".schema.json") || $0 == "tracking-plan.json" }

        #expect(actual == expected)
    }

    @Test("Schemas are ordered by their names' UTF-8 bytes, so uppercase comes before lowercase")
    func byteOrder() {
        let expected = ["Zulu", "apple", "zebra", "é"]
        let sut = TrackingPlan(schemas: ["é", "zebra", "Zulu", "apple"].map {
            EventSchema(name: $0, version: 1, consentCategory: .analytics, properties: [])
        })

        let actual = sut.schemas.map(\.name)

        #expect(actual == expected)
    }

    @Test("A name's bytes other than ASCII letters, digits, _ and - are percent-encoded in its file names")
    func fileNames() {
        let expected = [
            "tracking-plan.json",
            "Box%3CString%3E.v1.schema.json", "Box%3CString%3E.v1.example.json",
            "a%2Fb%20c.v1.schema.json", "a%2Fb%20c.v1.example.json",
            "caf%C3%A9.v1.schema.json", "caf%C3%A9.v1.example.json",
            "ok_name-1.v1.schema.json", "ok_name-1.v1.example.json",
            "tab%09.v1.schema.json", "tab%09.v1.example.json",
        ]
        let sut = TrackingPlan(schemas: ["Box<String>", "a/b c", "café", "ok_name-1", "tab\t"].map {
            EventSchema(name: $0, version: 1, consentCategory: .analytics, properties: [])
        })

        let actual = sut.files.map(\.path)

        #expect(actual == expected)
    }

    @Test("Quotes, backslashes and control characters in a name are escaped, and other characters kept")
    func escaping() throws {
        let expectedTitle = #"  "title": "say \"hi\" \\ to\n\r\t\b\f\u0001\u001Fé","#
        let sut = TrackingPlan(schemas: [EventSchema(name: "say \"hi\" \\ to\n\r\t\u{08}\u{0C}\u{01}\u{1F}é", version: 1, consentCategory: .analytics, properties: [])])

        let actual = try #require(sut.files.last { $0.path.hasSuffix(".schema.json") })

        #expect(String(decoding: actual.contents, as: UTF8.self).split(separator: "\n").contains { $0 == expectedTitle })
    }

    @Test("The checked spelling throws emptyEventName for a schema with no name")
    func checkedEmptyName() {
        let schemas = [EventSchema(name: "", version: 1, consentCategory: .analytics, properties: [])]

        #expect(throws: TrackingPlanError.emptyEventName) {
            try TrackingPlan(checkedSchemas: schemas)
        }
    }

    @Test("The checked spelling throws duplicateProperty for a schema listing a property twice")
    func checkedDuplicateProperty() {
        let property = EventSchema.Property(name: "plan", typeName: "String", isOptional: false)
        let schemas = [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [property, property])]

        #expect(throws: TrackingPlanError.duplicateProperty) {
            try TrackingPlan(checkedSchemas: schemas)
        }
    }

    @Test("The checked spelling throws duplicateEvent for two schemas of one name and version")
    func checkedDuplicateEvent() {
        let schemas = [
            EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: []),
            EventSchema(name: "signed_up", version: 1, consentCategory: .advertising, properties: []),
        ]

        #expect(throws: TrackingPlanError.duplicateEvent) {
            try TrackingPlan(checkedSchemas: schemas)
        }
    }

    @Test("The checked spelling throws duplicateEvent for names that differ only in case, even with names between them")
    func checkedCaseOnly() {
        let schemas = ["SignedUp", "Search", "signedUp"].map {
            EventSchema(name: $0, version: 1, consentCategory: .analytics, properties: [])
        }

        #expect(throws: TrackingPlanError.duplicateEvent) {
            try TrackingPlan(checkedSchemas: schemas)
        }
    }

    @Test("The checked spelling makes the plain spelling's plan from valid schemas")
    func checkedValid() throws {
        let schemas = [SignedUp.schema, CheckoutStarted.schema]
        let expected = TrackingPlan(schemas: schemas)

        let actual = try TrackingPlan(checkedSchemas: schemas)

        #expect(actual == expected)
        #expect(actual.schemas == [CheckoutStarted.schema, SignedUp.schema])
    }
}
