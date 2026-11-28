// The encoder's events checked by a JSON Schema validator (swift-json-schema) against the schemas
// the plan's Iglu export writes, as Snowplow's enrichment checks each self-describing event
// against the schema its URI names, looked up in the Iglu registry.

import EventMacros
import Foundation
import HTTPDestinations
import JSONSchema
import SnowplowEncoding
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("SnowplowBatchEncoder: validation against the Iglu export")
private struct SnowplowIgluValidationTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
        var seats: Int
        var discount: Double
        var trialEndsAt: Date
        var tags: [String]
    }

    @Test("An encoded event validates against the exported schema its URI names, at the path the URI gives")
    func validates() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let sut = try SnowplowBatchEncoder(vendor: "com.example.shop", appID: "shop-ios", plan: plan)
        var record = EventRecord(
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), referrer: nil, seats: 3, discount: 0.25, trialEndsAt: Date(timeIntervalSince1970: 1_796_652_207), tags: ["beta"]),
            timestamp: Date(timeIntervalSince1970: 1_795_442_607),
            sourceLocation: nil
        )
        record.revealsSensitiveValues = true
        let files = try plan.igluFiles(vendor: "com.example.shop", registry: .server, carryingForward: [])
        let body = try JSONValue.parse(String(decoding: try #require(sut.requests(for: [record]).requests.first).body.body, as: UTF8.self))
        let ue = try JSONValue.parse(try #require(body.object?["data"]?.array?.first?.object?["ue_pr"]?.string))
        let event = try #require(ue.object?["data"]?.object)
        let uri = try #require(event["schema"]?.string)
        let data = try #require(event["data"])
        // iglu:<vendor>/<name>/jsonschema/<version> is the file schemas/<vendor>/<name>/jsonschema/<version>.
        let path = "schemas/" + uri.dropFirst("iglu:".count)
        let file = try #require(files.first { $0.path == path })
        let schema = try Schema(instance: String(decoding: file.contents, as: UTF8.self))

        let actual = schema.validate(data)

        #expect(actual.isValid)
    }

    @Event(name: "upgraded")
    struct Upgraded {
        var plan: String
        var coupon: String?
    }

    @Test("An event carrying an optional property added at its version validates against the N-0-1 the export writes for Iglu Server, which supersedes the N-0-0 it fails")
    func validatesAgainstAddition() throws {
        // The schema published before the property was added: Upgraded without coupon.
        let published = EventSchema(name: "upgraded", version: 1, consentCategory: Upgraded.schema.consentCategory, properties: [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
        ])
        let original = try TrackingPlan(schemas: [published]).igluFiles(vendor: "com.example.shop", registry: .server, carryingForward: [])
        let plan = try TrackingPlan(schemas: [Upgraded.schema])
        let files = try plan.igluFiles(vendor: "com.example.shop", registry: .server, carryingForward: original)
        let sut = try SnowplowBatchEncoder(vendor: "com.example.shop", appID: "shop-ios", plan: plan)
        let record = EventRecord(event: Upgraded(plan: "pro", coupon: "SPRING"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let body = try JSONValue.parse(String(decoding: try #require(sut.requests(for: [record]).requests.first).body.body, as: UTF8.self))
        let ue = try JSONValue.parse(try #require(body.object?["data"]?.array?.first?.object?["ue_pr"]?.string))
        let event = try #require(ue.object?["data"]?.object)
        let data = try #require(event["data"])
        let expectedURI = "iglu:com.example.shop/upgraded/jsonschema/1-0-0"
        let addition = try #require(files.first { $0.path == "schemas/com.example.shop/upgraded/jsonschema/1-0-1" })
        let model = try #require(original.first { $0.path == "schemas/com.example.shop/upgraded/jsonschema/1-0-0" })

        let modelSchema = try Schema(instance: String(decoding: model.contents, as: UTF8.self))

        let actual = try Schema(instance: String(decoding: addition.contents, as: UTF8.self)).validate(data)

        #expect(event["schema"]?.string == expectedURI)
        #expect(actual.isValid)
        #expect(!modelSchema.validate(data).isValid)
    }

    // Iglu Central's own schemas, vendored from https://github.com/snowplow/iglu-central
    // (schemas/com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4,
    // .../mobile_context/jsonschema/1-0-3 and com.snowplowanalytics.mobile/application/jsonschema/1-0-0,
    // fetched on 2026-11-27), so the check doesn't rest on reading them by hand.
    @Test("The hand-worked request's events validate against Iglu Central's payload_data 1-0-4, and each entity in co against the Iglu Central schema its URI names")
    func handWorkedAgainstIgluCentral() throws {
        let fixture = try #require(Bundle.module.url(forResource: "hand-worked-batch", withExtension: "json", subdirectory: "Fixtures"))
        let payloadDataURL = try #require(Bundle.module.url(forResource: "iglu-central-payload_data-1-0-4", withExtension: "json", subdirectory: "Fixtures"))
        let mobileContextURL = try #require(Bundle.module.url(forResource: "iglu-central-mobile_context-1-0-3", withExtension: "json", subdirectory: "Fixtures"))
        let applicationURL = try #require(Bundle.module.url(forResource: "iglu-central-application-1-0-0", withExtension: "json", subdirectory: "Fixtures"))
        let schemas = [
            "iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4": try Schema(instance: String(decoding: try Data(contentsOf: payloadDataURL), as: UTF8.self)),
            "iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3": try Schema(instance: String(decoding: try Data(contentsOf: mobileContextURL), as: UTF8.self)),
            "iglu:com.snowplowanalytics.mobile/application/jsonschema/1-0-0": try Schema(instance: String(decoding: try Data(contentsOf: applicationURL), as: UTF8.self)),
        ]
        let body = try JSONValue.parse(String(decoding: try Data(contentsOf: fixture), as: UTF8.self))
        let events = try #require(body.object?["data"])
        let entities = try #require(events.array).compactMap { $0.object?["co"]?.string }.flatMap { co in
            (try? JSONValue.parse(co))?.object?["data"]?.array ?? []
        }
        let expectedEntitySchemas = [
            "iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3",
            "iglu:com.snowplowanalytics.mobile/application/jsonschema/1-0-0",
        ]

        let payloadData = try #require(schemas["iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4"]).validate(events)
        let actual = try entities.map { entity in
            let uri = try #require(entity.object?["schema"]?.string)
            let data = try #require(entity.object?["data"])
            return (uri, try #require(schemas[uri]).validate(data).isValid)
        }

        #expect(body.object?["schema"]?.string == "iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4")
        #expect(payloadData.isValid)
        #expect(actual.map(\.0) == expectedEntitySchemas)
        #expect(actual.map(\.1) == [true, true])
        // So the check can fail: an event without its required e, and a mobile_context without its required osType.
        let missingE = try JSONValue.parse(#"[{"p":"mob","tv":"traffluent"}]"#)
        let missingOSType = try JSONValue.parse(#"{"osVersion":"1","deviceManufacturer":"Apple Inc.","deviceModel":"x"}"#)
        #expect(!(schemas["iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4"]?.validate(missingE).isValid ?? true))
        #expect(!(schemas["iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3"]?.validate(missingOSType).isValid ?? true))
    }

    @Test("An event whose data breaks its exported schema fails validation, so the check can fail")
    func rejects() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let files = try plan.igluFiles(vendor: "com.example.shop", registry: .server, carryingForward: [])
        let file = try #require(files.first)
        let schema = try Schema(instance: String(decoding: file.contents, as: UTF8.self))
        let missingSeats = try JSONValue.parse(#"{"plan":"pro","discount":0.25,"trialEndsAt":"2026-12-07T14:03:27.000Z","tags":[]}"#)
        let wrongType = try JSONValue.parse(#"{"plan":"pro","seats":"3","discount":0.25,"trialEndsAt":"2026-12-07T14:03:27.000Z","tags":[]}"#)

        let actual = [schema.validate(missingSeats).isValid, schema.validate(wrongType).isValid]

        #expect(actual == [false, false])
    }
}
