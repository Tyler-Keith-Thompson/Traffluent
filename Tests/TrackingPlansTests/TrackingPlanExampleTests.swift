// Each event's example, its conformance vector: pinned byte for byte, and checked by a JSON Schema
// validator (swift-json-schema) against the event's own document.

import EventMacros
import Foundation
import JSONSchema
import PropertyBased
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("TrackingPlan: examples")
struct TrackingPlanExampleTests {
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

    struct Coordinate: Codable {
        var latitude: Double

    }

    @Event(name: "everything")
    struct Everything {
        var int8: Int8
        var uint32: UInt32
        var float: Float
        var nested: [[Bool]?]
        var maybe: Optional<Int64>
        var secret: Sensitive<[UUID]>?
        var location: Coordinate
    }

    @Test("An example sets an integer to 0 and an optional property to its wrapped type's example")
    func checkoutStarted() throws {
        let expected = """
            {
              "cartSize": 0,
              "coupon": "example"
            }

            """
        let sut = try TrackingPlan(schemas: [CheckoutStarted.schema])

        let actual = try #require(sut.files.first { $0.path == "checkout_started.v2.example.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An example sets a date to the reference date, a UUID to the nil UUID, a number to 0, an array to one element and a boolean to false")
    func orderCompleted() throws {
        let expected = """
            {
              "completedAt": "2001-01-01T00:00:00Z",
              "express": false,
              "itemCount": 0,
              "items": [
                "example"
              ],
              "orderID": "00000000-0000-0000-0000-000000000000",
              "total": 0
            }

            """
        let sut = try TrackingPlan(schemas: [OrderCompleted.schema])

        let actual = try #require(sut.files.first { $0.path == "order_completed.v1.example.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An example sets a Sensitive property to its value's example")
    func signedUp() throws {
        let expected = """
            {
              "email": "example",
              "plan": "example",
              "referrer": "example"
            }

            """
        let sut = try TrackingPlan(schemas: [SignedUp.schema])

        let actual = try #require(sut.files.first { $0.path == "signed_up.v1.example.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An example fills nested arrays and optionals, and sets a type the plan can't map to null")
    func everything() throws {
        let expected = """
            {
              "float": 0,
              "int8": 0,
              "location": null,
              "maybe": 0,
              "nested": [
                [
                  false
                ]
              ],
              "secret": [
                "00000000-0000-0000-0000-000000000000"
              ],
              "uint32": 0
            }

            """
        let sut = try TrackingPlan(schemas: [Everything.schema])

        let actual = try #require(sut.files.first { $0.path == "everything.v1.example.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("An event with no properties has an empty object as its example")
    func noProperties() throws {
        let expected = "{}\n"
        let sut = try TrackingPlan(schemas: [EventSchema(name: "app_opened", version: 1, consentCategory: .analytics, properties: [])])

        let actual = try #require(sut.files.first { $0.path == "app_opened.v1.example.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("Every fixture event's example is valid against its own document")
    func validates() throws {
        let sut = try TrackingPlan(schemas: [CheckoutStarted.schema, OrderCompleted.schema, SignedUp.schema, Everything.schema])
        let files = Dictionary(uniqueKeysWithValues: sut.files.map { ($0.path, String(decoding: $0.contents, as: UTF8.self)) })

        for schema in sut.schemas {
            let document = try #require(files["\(schema.name).v\(schema.version).schema.json"])
            let example = try #require(files["\(schema.name).v\(schema.version).example.json"])

            let actual = try Schema(instance: document).validate(instance: example)

            #expect(actual.isValid, "\(schema.name)")
        }
    }

    @Test("Any schema's example is valid against its document", .tags(.randomized))
    func anyValidates() async throws {
        let typeNames = ["String", "Int", "UInt8", "Int32", "Int8", "UInt64", "Double", "Float", "Bool", "Date", "UUID", "[String]", "[[Int]?]", "Sensitive<Int>", "Coordinate", "[Int: Int]"]
        await propertyCheck(count: 200, input: Gen.int(in: 0 ... 15).array(of: 0 ... 10), Gen.bool.array(of: 10 ... 10)) { types, optionals in
            let properties = types.enumerated().map { index, type in
                EventSchema.Property(name: "p\(index)", typeName: typeNames[type], isOptional: optionals[index])
            }
            let sut = try TrackingPlan(schemas: [EventSchema(name: "event", version: 1, consentCategory: .analytics, properties: properties)])
            let document = String(decoding: sut.files.first { $0.path == "event.v1.schema.json" }?.contents ?? [], as: UTF8.self)
            let example = String(decoding: sut.files.first { $0.path == "event.v1.example.json" }?.contents ?? [], as: UTF8.self)

            let actual = try? Schema(instance: document).validate(instance: example)

            #expect(actual?.isValid == true)
        }
    }
}
