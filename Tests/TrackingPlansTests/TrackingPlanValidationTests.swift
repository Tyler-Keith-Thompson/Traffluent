// The exported documents checked by a JSON Schema validator (swift-json-schema): against draft
// 2020-12's meta-schema, and as schemas that accept the events they describe and reject others. The
// meta-schema comes from TraffluentTestSupport rather than the validator's resource bundle, which a
// Bazel test executable can't find.

import EventMacros
import Foundation
import JSONSchema
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("TrackingPlan: validation")
struct TrackingPlanValidationTests {
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

    struct Coordinate: BinaryCodable {
        var latitude: Double

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            var map = try decoder.decodeMap()
            latitude = try map.decode(forKey: "latitude")
        }

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encodeMap { map in
                map.encode(latitude, forKey: "latitude")
            }
        }
    }

    @Event(name: "Box<String>")
    struct Everything {
        var int8: Int8
        var uint32: UInt32
        var float: Float
        var nested: [[Bool]?]
        var maybe: Optional<Int64>
        var secret: Sensitive<[UUID]>?
        var location: Coordinate
    }

    @Test("Every document of a fixture app's plan is valid against draft 2020-12's meta-schema")
    func metaSchema() throws {
        let remotes = try Draft202012MetaSchema.documents.mapValues { try JSONValue.parse($0) }
        let metaSchema = try Schema(
            rawSchema: try #require(remotes[Draft202012MetaSchema.id]),
            context: Context(dialect: .draft2020_12, remoteSchema: remotes),
            baseURI: try #require(URL(string: Draft202012MetaSchema.id))
        )
        let sut = try TrackingPlan(schemas: [CheckoutStarted.schema, OrderCompleted.schema, SignedUp.schema, Everything.schema])
        let documents = sut.files.filter { $0.path.hasSuffix(".schema.json") }

        for document in documents {
            let schema = try JSONValue.parse(String(decoding: document.contents, as: UTF8.self))

            let actual = metaSchema.validate(schema)

            #expect(actual.isValid, "\(document.path)")
        }
    }

    @Test("The meta-schema check rejects a document that isn't a schema, so its passes mean something")
    func metaSchemaRejects() throws {
        let remotes = try Draft202012MetaSchema.documents.mapValues { try JSONValue.parse($0) }
        let metaSchema = try Schema(
            rawSchema: try #require(remotes[Draft202012MetaSchema.id]),
            context: Context(dialect: .draft2020_12, remoteSchema: remotes),
            baseURI: try #require(URL(string: Draft202012MetaSchema.id))
        )
        let invalid: JSONValue = ["type": "object", "required": "cartSize"]

        let actual = metaSchema.validate(invalid)

        #expect(!actual.isValid)
    }

    @Test("A document accepts the event it describes, with an optional property absent or null")
    func accepts() throws {
        let sut = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let document = try #require(sut.files.last { $0.path.hasSuffix(".schema.json") })
        let schema = try Schema(instance: String(decoding: document.contents, as: UTF8.self))
        let instances = [
            #"{"cartSize": 3, "coupon": "SPRING"}"#,
            #"{"cartSize": 3}"#,
            #"{"cartSize": 3, "coupon": null}"#,
        ]

        for instance in instances {
            let actual = try schema.validate(instance: instance)

            #expect(actual.isValid, "\(instance)")
        }
    }

    @Test("A document rejects an event missing a required property, with an extra one, or with a value of the wrong type")
    func rejects() throws {
        let sut = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let document = try #require(sut.files.last { $0.path.hasSuffix(".schema.json") })
        let schema = try Schema(instance: String(decoding: document.contents, as: UTF8.self))
        let instances = [
            #"{"coupon": "SPRING"}"#,
            #"{"cartSize": 3, "currency": "EUR"}"#,
            #"{"cartSize": "3"}"#,
            #"{"cartSize": 3.5}"#,
            #"{"cartSize": null}"#,
            #"[]"#,
        ]

        for instance in instances {
            let actual = try schema.validate(instance: instance)

            #expect(!actual.isValid, "\(instance)")
        }
    }

    @Test("A bounded integer's document rejects a value outside the type's range")
    func bounds() throws {
        let sut = try TrackingPlan(schemas: [OrderCompleted.schema])
        let document = try #require(sut.files.last { $0.path.hasSuffix(".schema.json") })
        let schema = try Schema(instance: String(decoding: document.contents, as: UTF8.self))
        let valid = #"{"orderID": "6BA7B810-9DAD-11D1-80B4-00C04FD430C8", "total": 9.5, "itemCount": 65535, "items": ["lid"], "completedAt": "2026-11-22T10:00:00Z", "express": false}"#
        let invalid = #"{"orderID": "6BA7B810-9DAD-11D1-80B4-00C04FD430C8", "total": 9.5, "itemCount": 65536, "items": ["lid"], "completedAt": "2026-11-22T10:00:00Z", "express": false}"#

        let actualValid = try schema.validate(instance: valid)
        let actualInvalid = try schema.validate(instance: invalid)

        #expect(actualValid.isValid)
        #expect(!actualInvalid.isValid)
    }
}
