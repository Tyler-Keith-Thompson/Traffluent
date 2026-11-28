// The example of the PropertyJSON module's landing article
// (Sources/PropertyJSON/PropertyJSON.docc/PropertyJSON.md), verbatim, so the article cannot drift
// from the code.

import EventMacros
import Foundation
import Instrumentation
import JSONValues
import PropertyJSON
import Testing
import TrackingPlans
import Traffluent

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("PropertyJSON module examples")
private struct PropertyJSONModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("A record as a vendor's JSON")
    func recordAsJSON() throws {
        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let record = EventRecord(
            id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            event: SignedUp(plan: "pro"),
            timestamp: Date(timeIntervalSince1970: 1.5),
            sourceLocation: nil,
            context: context
        )

        let reader = PropertyReader(plan: plan)
        let event: JSON = .object([
            "name": .string(record.name),
            "id": .string(record.deduplicationID),
            "user": .string(record.pseudonymousIdentity.uuid.uuidString.lowercased()),
            "at": .integer(try record.timestamp.millisecondsSince1970()),
            "properties": .object(try reader.properties(of: record, includingSensitiveValues: false)),
            "context": .object(try record.standardContext.flattened()),
        ])

        let expected = #"{"at":1500,"context":{"operatingSystem.name":"iOS","operatingSystem.version":"26.1.0"},"id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","name":"signed_up","properties":{"plan":"pro"},"user":"00000000-0000-4000-8000-00000000000a"}"#
        #expect(event.minified == expected)
    }
}
