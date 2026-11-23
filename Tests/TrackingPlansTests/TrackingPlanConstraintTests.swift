// Constraint keywords in the exported plan: pinned byte for byte, valid against draft 2020-12's
// meta-schema, honoured by each example, and enforced by a JSON Schema validator
// (swift-json-schema).

import EventMacros
import Foundation
import JSONSchema
import PropertyBased
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("TrackingPlan: constraints")
struct TrackingPlanConstraintTests {
    enum CouponCode: Refinement {
        static let constraints: [Constraint<String>] = [
            .pattern("^[A-Z0-9]+$", example: "SPRING"),
            .pattern("^.{6}$", example: "SPRING"),
        ]
    }

    enum Seats: Refinement {
        static let constraints: [Constraint<Int8>] = [.minimum(1), .maximum(100)]
    }

    @Event(name: "search_performed")
    struct SearchPerformed {
        @Constrained(.minLength(10), .maxLength(200))
        var query: String
        @Constrained(.maxLength(3))
        var country: String?
        @Constrained(.minimum(-5), .maximum(-1))
        var offset: Int
        @Constrained(.minimum(0.25), .maximum(0.75))
        var ratio: Double
        @Constrained(.minItems(2), .maxItems(3))
        var filters: [String]
        @Constrained(.maxItems(0))
        var none: [Bool]
    }

    @Event(name: "coupon_applied")
    struct CouponApplied {
        var code: Refined<String, CouponCode>
        var seats: Sensitive<Refined<Int8, Seats>>?
    }

    static let expectedSearch = """
        {
          "$id": "search_performed.v1.schema.json",
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "additionalProperties": false,
          "properties": {
            "country": {
              "maxLength": 3,
              "type": [
                "string",
                "null"
              ]
            },
            "filters": {
              "items": {
                "type": "string"
              },
              "maxItems": 3,
              "minItems": 2,
              "type": "array"
            },
            "none": {
              "items": {
                "type": "boolean"
              },
              "maxItems": 0,
              "type": "array"
            },
            "offset": {
              "maximum": -1,
              "minimum": -5,
              "type": "integer"
            },
            "query": {
              "maxLength": 200,
              "minLength": 10,
              "type": "string"
            },
            "ratio": {
              "maximum": 0.75,
              "minimum": 0.25,
              "type": "number"
            }
          },
          "required": [
            "query",
            "offset",
            "ratio",
            "filters",
            "none"
          ],
          "title": "search_performed",
          "type": "object",
          "x-traffluent-consent-category": "analytics",
          "x-traffluent-version": 1
        }

        """

    @Test("Declared keywords are written beside each property's type: lengths, bounds, fractional bounds and counts")
    func declaredDocument() throws {
        let sut = TrackingPlan(schemas: [SearchPerformed.schema])

        let actual = try #require(sut.files.first { $0.path == "search_performed.v1.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == Self.expectedSearch)
    }

    @Test("A refined property is its value's type with its rule's keywords: one pattern with its example, the rest under allOf, and bounds that replace the type's looser ones")
    func refinedDocument() throws {
        let expected = """
            {
              "$id": "coupon_applied.v1.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {
                "code": {
                  "allOf": [
                    {
                      "pattern": "^.{6}$"
                    }
                  ],
                  "examples": [
                    "SPRING"
                  ],
                  "pattern": "^[A-Z0-9]+$",
                  "type": "string"
                },
                "seats": {
                  "maximum": 100,
                  "minimum": 1,
                  "type": [
                    "integer",
                    "null"
                  ],
                  "x-traffluent-sensitive": true
                }
              },
              "required": [
                "code"
              ],
              "title": "coupon_applied",
              "type": "object",
              "x-traffluent-consent-category": "analytics",
              "x-traffluent-version": 1
            }

            """
        let sut = TrackingPlan(schemas: [CouponApplied.schema])

        let actual = try #require(sut.files.first { $0.path == "coupon_applied.v1.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("Each example meets its keywords: a pattern's example, x repeated to a minLength, a string cut to a maxLength, bounds' nearest values and counts")
    func examples() throws {
        let expectedSearch = """
            {
              "country": "exa",
              "filters": [
                "example",
                "example"
              ],
              "none": [],
              "offset": -1,
              "query": "xxxxxxxxxx",
              "ratio": 0.25
            }

            """
        let expectedCoupon = """
            {
              "code": "SPRING",
              "seats": 1
            }

            """
        let sut = TrackingPlan(schemas: [SearchPerformed.schema, CouponApplied.schema])

        let search = try #require(sut.files.first { $0.path == "search_performed.v1.example.json" })
        let coupon = try #require(sut.files.first { $0.path == "coupon_applied.v1.example.json" })

        #expect(String(decoding: search.contents, as: UTF8.self) == expectedSearch)
        #expect(String(decoding: coupon.contents, as: UTF8.self) == expectedCoupon)
    }

    @Test("A keyword looser than the type's own bound keeps the type's; a whole number's example meets a fractional bound with the next whole number")
    func mergedBounds() throws {
        let expectedDocument = #"{"maximum": 127, "minimum": 1, "type": "integer"}"#
        let expectedExample = #"{"p": 1, "q": 1}"#
        let sut = TrackingPlan(schemas: [EventSchema(name: "e", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "p", typeName: "Int8", isOptional: false, keywords: [.minimum(1), .maximum(200)]),
            EventSchema.Property(name: "q", typeName: "Int", isOptional: false, keywords: [.minimum(0.5), .maximum(1.5)]),
        ])])
        let document = try #require(sut.files.first { $0.path == "e.v1.schema.json" })
        let example = try #require(sut.files.first { $0.path == "e.v1.example.json" })

        let actualDocument = try JSONValue.parse(String(decoding: document.contents, as: UTF8.self))
        let actualExample = try JSONValue.parse(String(decoding: example.contents, as: UTF8.self))

        #expect(actualDocument.object?["properties"]?.object?["p"] == (try JSONValue.parse(expectedDocument)))
        #expect(actualExample == (try JSONValue.parse(expectedExample)))
        #expect(try Schema(instance: String(decoding: document.contents, as: UTF8.self)).validate(instance: String(decoding: example.contents, as: UTF8.self)).isValid)
    }

    @Test("Two keywords of one kind, a refined type's and a declared one, write the tighter: the larger minLength and the smaller maxLength")
    func repeatedKeywords() throws {
        let expected = try JSONValue.parse(#"{"maxLength": 5, "minLength": 3, "type": "string"}"#)
        let sut = TrackingPlan(schemas: [EventSchema(name: "e", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "p", typeName: "String", isOptional: false, keywords: [.minLength(1), .maxLength(5), .minLength(3), .maxLength(9)]),
        ])])
        let document = try #require(sut.files.first { $0.path == "e.v1.schema.json" })

        let actual = try JSONValue.parse(String(decoding: document.contents, as: UTF8.self)).object?["properties"]?.object?["p"]

        #expect(actual == expected)
    }

    @Test("A type the plan can't map, or can't parse, keeps its keywords beside the Swift type it records", arguments: ["CouponCode", "Box<String"])
    func unmappedTypeKeywords(typeName: String) throws {
        let expected: JSONValue = ["minLength": 2, "x-traffluent-swift-type": .string(typeName)]
        let sut = TrackingPlan(schemas: [EventSchema(name: "e", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "p", typeName: typeName, isOptional: false, keywords: [.minLength(2)]),
        ])])
        let document = try #require(sut.files.first { $0.path == "e.v1.schema.json" })

        let actual = try JSONValue.parse(String(decoding: document.contents, as: UTF8.self)).object?["properties"]?.object?["p"]

        #expect(actual == expected)
    }

    @Test("Documents with keywords are valid against draft 2020-12's meta-schema")
    func metaSchema() throws {
        let remotes = try Draft202012MetaSchema.documents.mapValues { try JSONValue.parse($0) }
        let metaSchema = try Schema(
            rawSchema: try #require(remotes[Draft202012MetaSchema.id]),
            context: Context(dialect: .draft2020_12, remoteSchema: remotes),
            baseURI: try #require(URL(string: Draft202012MetaSchema.id))
        )
        let sut = TrackingPlan(schemas: [SearchPerformed.schema, CouponApplied.schema])
        let documents = sut.files.filter { $0.path.hasSuffix(".schema.json") }

        for document in documents {
            let schema = try JSONValue.parse(String(decoding: document.contents, as: UTF8.self))

            let actual = metaSchema.validate(schema)

            #expect(actual.isValid, "\(document.path)")
        }
    }

    @Test("Each example is valid against its document")
    func examplesValidate() throws {
        let sut = TrackingPlan(schemas: [SearchPerformed.schema, CouponApplied.schema])
        let files = Dictionary(uniqueKeysWithValues: sut.files.map { ($0.path, String(decoding: $0.contents, as: UTF8.self)) })

        for schema in sut.schemas {
            let document = try #require(files["\(schema.name).v\(schema.version).schema.json"])
            let example = try #require(files["\(schema.name).v\(schema.version).example.json"])

            let actual = try Schema(instance: document).validate(instance: example)

            #expect(actual.isValid, "\(schema.name)")
        }
    }

    @Test("A validator rejects a payload that breaks any one keyword", arguments: [
        #"{"code": "spring", "seats": 1}"#,
        #"{"code": "SPRINGS", "seats": 1}"#,
        #"{"code": "SPRING", "seats": 0}"#,
        #"{"code": "SPRING", "seats": 101}"#,
    ])
    func validatorRejects(payload: String) throws {
        let sut = TrackingPlan(schemas: [CouponApplied.schema])
        let document = String(decoding: try #require(sut.files.first { $0.path == "coupon_applied.v1.schema.json" }).contents, as: UTF8.self)

        let actual = try Schema(instance: document).validate(instance: payload)

        #expect(!actual.isValid)
    }

    @Test("A plan with fractional bounds checks clean against its own files, which parse back to the same numbers")
    func fractionalRoundTrip() {
        let sut = TrackingPlan(schemas: [SearchPerformed.schema, CouponApplied.schema])

        let actual = sut.check(against: sut.files)

        #expect(actual == .matches)
    }

    @Test("A bound beyond Int64's range is written as a number and reads back equal", arguments: [1e20, -1e20, 0.1, 1e-5])
    func largeBounds(bound: Double) {
        let sut = TrackingPlan(schemas: [EventSchema(name: "e", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "p", typeName: "Double", isOptional: false, keywords: [.maximum(bound)]),
        ])])

        let actual = sut.check(against: sut.files)

        #expect(actual == .matches)
    }

    @Test("Any set of keywords on a string, integer, number or array gives an example its document accepts", .tags(.randomized))
    func anyValidates() async {
        await propertyCheck(count: 200, input: Gen.int(in: 0 ... 3), Gen.int(in: 0 ... 12), Gen.int(in: 0 ... 12), Gen.int(in: -20 ... 20), Gen.int(in: 0 ... 20)) { kind, lower, span, bound, width in
            let (typeName, keywords): (String, [ValidationKeyword]) = switch kind {
            case 0: ("String", [.minLength(lower), .maxLength(lower + span)])
            // At least 1 wide, so a whole number always fits between the bounds.
            case 1: ("Int", [.minimum(Double(bound) / 4), .maximum(Double(bound) / 4 + Double(width) + 1)])
            case 2: ("Double", [.minimum(Double(bound) / 4), .maximum(Double(bound) / 4 + Double(width) / 8)])
            default: ("[Int]", [.minItems(lower), .maxItems(lower + span)])
            }
            let sut = TrackingPlan(schemas: [EventSchema(name: "event", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "p", typeName: typeName, isOptional: false, keywords: keywords),
            ])])
            let document = String(decoding: sut.files.first { $0.path == "event.v1.schema.json" }?.contents ?? [], as: UTF8.self)
            let example = String(decoding: sut.files.first { $0.path == "event.v1.example.json" }?.contents ?? [], as: UTF8.self)

            let actual = try? Schema(instance: document).validate(instance: example)

            #expect(actual?.isValid == true, "\(typeName) \(keywords)")
        }
    }
}
