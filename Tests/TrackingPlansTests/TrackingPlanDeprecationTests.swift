// A property removed at the same version stays in the event's document, with the schema it had,
// marked deprecated and not required, so the payloads of releases that sent it still validate. The
// check and the export carry it forward from the committed plan, and declaring it again is compared
// with that schema.

import EventMacros
import Foundation
import JSONSchema
import Testing
import TrackingPlans

@Suite("TrackingPlan: deprecated properties")
struct TrackingPlanDeprecationTests {
    @Event(name: "checkout_started")
    struct Released {
        var cartSize: Int
        var coupon: String?
        var screen: String
    }

    @Event(name: "checkout_started")
    struct Removed {
        var cartSize: Int
    }

    @Event(name: "checkout_started")
    struct ScreenRetyped {
        var cartSize: Int
        var screen: Int
    }

    @Event(name: "checkout_started")
    struct CouponRestored {
        var cartSize: Int
        var coupon: String?
    }

    @Event(name: "checkout_started")
    struct ScreenRestored {
        var cartSize: Int
        var screen: String
    }

    @Event(name: "checkout_started")
    struct Compatible {
        var cartSize: Int
        var coupon: String?
        var currency: String = "USD"
    }

    @Event(name: "checkout_started", version: 2)
    struct RemovedVersion2 {
        var cartSize: Int
    }

    @Test("A removed property stays in its version's document with the schema it had, marked deprecated, and out of required")
    func removedKept() throws {
        let committed = try TrackingPlan(schemas: [Released.schema]).files
        let sut = try TrackingPlan(schemas: [Removed.schema])
        let expected = """
            {
              "$id": "checkout_started.v1.schema.json",
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "additionalProperties": false,
              "properties": {
                "cartSize": {
                  "type": "integer"
                },
                "coupon": {
                  "deprecated": true,
                  "type": [
                    "string",
                    "null"
                  ]
                },
                "screen": {
                  "deprecated": true,
                  "type": "string"
                }
              },
              "required": [
                "cartSize"
              ],
              "title": "checkout_started",
              "type": "object",
              "x-traffluent-consent-category": "analytics",
              "x-traffluent-version": 1
            }

            """

        let actual = try #require(sut.files(carryingForward: committed).first { $0.path == "checkout_started.v1.schema.json" })

        #expect(String(decoding: actual.contents, as: UTF8.self) == expected)
    }

    @Test("The check reports a removal as compatible, and a plan exported with it carried forward matches, and keeps matching on the next export")
    func carriedForward() throws {
        let released = try TrackingPlan(schemas: [Released.schema]).files
        let sut = try TrackingPlan(schemas: [Removed.schema])
        let expectedRemoval = TrackingPlanCheck.outOfDate([
            .propertyRemoved(event: "checkout_started", version: 1, property: "coupon"),
            .propertyRemoved(event: "checkout_started", version: 1, property: "screen"),
        ])
        let exported = sut.files(carryingForward: released)

        let actualRemoval = sut.check(against: released)
        let actualExported = sut.check(against: exported)
        let actualReexported = sut.check(against: sut.files(carryingForward: exported))

        #expect(actualRemoval == expectedRemoval)
        #expect(actualExported == .matches)
        #expect(actualReexported == .matches)
    }

    @Test("Declaring a deprecated property again with another type is breaking, reported as a retyping from the schema it had, and as required again")
    func restoredRetyped() throws {
        let committed = try TrackingPlan(schemas: [Removed.schema]).files(carryingForward: try TrackingPlan(schemas: [Released.schema]).files)
        let sut = try TrackingPlan(schemas: [ScreenRetyped.schema])
        let expected = TrackingPlanCheck.breaking([
            .propertyRetyped(event: "checkout_started", version: 1, property: "screen", committed: #"{"type": "string"}"#, current: #"{"type": "integer"}"#),
            .requiredPropertyAdded(event: "checkout_started", version: 1, property: "screen"),
        ])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("Declaring a deprecated optional property again with the schema it had is compatible: the committed plan is only out of date")
    func restoredSameSchema() throws {
        let committed = try TrackingPlan(schemas: [Removed.schema]).files(carryingForward: try TrackingPlan(schemas: [Released.schema]).files)
        let sut = try TrackingPlan(schemas: [CouponRestored.schema])
        let expected = TrackingPlanCheck.outOfDate([
            .fileOutOfDate(path: "checkout_started.v1.example.json"),
            .fileOutOfDate(path: "checkout_started.v1.schema.json"),
        ])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("Declaring a deprecated property again as required, with the type it had, is breaking: records and payloads written while it was gone lack it")
    func restoredRequired() throws {
        let committed = try TrackingPlan(schemas: [Removed.schema]).files(carryingForward: try TrackingPlan(schemas: [Released.schema]).files)
        let sut = try TrackingPlan(schemas: [ScreenRestored.schema])
        let expected = TrackingPlanCheck.breaking([.requiredPropertyAdded(event: "checkout_started", version: 1, property: "screen")])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("An earlier release's payload, holding a property removed since and lacking one added with a default value, validates against the current document")
    func earlierPayloadValidates() throws {
        let committed = try TrackingPlan(schemas: [Released.schema]).files
        let sut = try TrackingPlan(schemas: [Compatible.schema])
        let document = try #require(sut.files(carryingForward: committed).first { $0.path == "checkout_started.v1.schema.json" })
        let schema = try Schema(instance: String(decoding: document.contents, as: UTF8.self))
        let earlier = #"{"cartSize": 3, "coupon": null, "screen": "Cart"}"#
        let current = #"{"cartSize": 3, "coupon": "SPRING", "currency": "EUR"}"#
        let retyped = #"{"cartSize": 3, "screen": 3}"#

        let actualEarlier = try schema.validate(instance: earlier)
        let actualCurrent = try schema.validate(instance: current)
        let actualRetyped = try schema.validate(instance: retyped)

        #expect(actualEarlier.isValid)
        #expect(actualCurrent.isValid)
        #expect(!actualRetyped.isValid)
    }

    @Test("A raised version's document starts without the earlier version's removed properties: its files are the plan's own")
    func raisedVersionNotCarried() throws {
        let committed = try TrackingPlan(schemas: [Released.schema]).files
        let sut = try TrackingPlan(schemas: [RemovedVersion2.schema])
        let expected = Array(sut.files.dropFirst())

        let actual = sut.files(carryingForward: committed).filter { $0.path.hasPrefix("checkout_started.v2.") }

        #expect(actual == expected)
    }

    @Test("Writing a plan over a directory keeps, marked deprecated, the properties the plan there has and the events no longer declare")
    func writeCarriesForward() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TrackingPlanDeprecationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try TrackingPlan(schemas: [Released.schema]).write(to: directory)
        let sut = try TrackingPlan(schemas: [Removed.schema])
        let expected = sut.files(carryingForward: try TrackingPlan(schemas: [Released.schema]).files).first { $0.path == "checkout_started.v1.schema.json" }?.contents

        try sut.write(to: directory)

        let actual = FileManager.default.contents(atPath: directory.appendingPathComponent("checkout_started.v1.schema.json").path).map(Array.init)
        #expect(actual == expected)
        #expect(sut.check(againstDirectory: directory) == .matches)
    }
}
