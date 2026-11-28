// The encoder's records checked by a JSON Schema validator (swift-json-schema) against the documents
// of the plan it encodes with, as a collector that validates against the exported plan checks them.

import CollectorEncoding
import Destinations
import EventMacros
import Foundation
import Instrumentation
import JSONSchema
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("CollectorBatchEncoder: validation against the plan")
private struct CollectorPlanValidationTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var backupEmail: Sensitive<String>?
        var recoveryCodes: [Sensitive<String>]
        var verifiedAt: Sensitive<Date>
    }

    @Test("A record whose Sensitive values redactingSensitiveValues() redacted validates against its event's document")
    func redacted() async throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let document = try #require(plan.files.first { $0.path == "signed_up.v1.schema.json" })
        let schema = try Schema(instance: String(decoding: document.contents, as: UTF8.self))
        let sink = InMemoryDestination.unbounded()
        let destination = sink.redactingSensitiveValues()
        var record = EventRecord(
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), backupEmail: Sensitive("ada@example.org"), recoveryCodes: [Sensitive("1234")], verifiedAt: Sensitive(Date(timeIntervalSince1970: 60))),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil
        )
        record.revealsSensitiveValues = true
        await destination.receive([record])
        let body = try JSONValue.parse(String(decoding: try #require(encoder.batch(of: sink.records).body).body, as: UTF8.self))
        let properties = try #require(body.object?["records"]?.array?.first?.object?["properties"])
        let expectedNames: Set<String> = ["plan", "recoveryCodes"]

        let actual = schema.validate(properties)

        #expect(actual.isValid)
        #expect(properties.object.map { Set($0.keys) } == expectedNames)
    }

    @Test("A record that reveals its Sensitive values validates against its event's document")
    func revealed() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let encoder = CollectorBatchEncoder(plan: plan, instrument: NoOpInstrument())
        let document = try #require(plan.files.first { $0.path == "signed_up.v1.schema.json" })
        let schema = try Schema(instance: String(decoding: document.contents, as: UTF8.self))
        var record = EventRecord(
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), backupEmail: nil, recoveryCodes: [Sensitive("1234")], verifiedAt: Sensitive(Date(timeIntervalSince1970: 60))),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil
        )
        record.revealsSensitiveValues = true
        let body = try JSONValue.parse(String(decoding: try #require(encoder.batch(of: [record]).body).body, as: UTF8.self))
        let properties = try #require(body.object?["records"]?.array?.first?.object?["properties"])
        let expectedNames: Set<String> = ["backupEmail", "email", "plan", "recoveryCodes", "verifiedAt"]

        let actual = schema.validate(properties)

        #expect(actual.isValid)
        #expect(properties.object.map { Set($0.keys) } == expectedNames)
    }
}
