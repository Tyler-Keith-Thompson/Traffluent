import CollectorEncoding
import Destinations
import EventMacros
import Foundation
import Instrumentation
import StandardContext
import Testing
import TrackingPlans

@Suite("CollectorBatchEncoder: sensitive values")
struct CollectorSensitiveValueTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var backupEmail: Sensitive<String>?
        var recoveryCodes: [Sensitive<String>]
        var verifiedAt: Sensitive<Date>
    }

    @Test("A record that reveals its sensitive values sends them as their values")
    func revealed() throws {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [SignedUp.schema]), instrument: NoOpInstrument())
        var context = ServiceContext.topLevel
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!)
        var record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), backupEmail: Sensitive("ada@example.org"), recoveryCodes: [Sensitive("1234")], verifiedAt: Sensitive(Date(timeIntervalSince1970: 60))),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            context: context
        )
        record.revealsSensitiveValues = true
        let expected = #"{"records":[{"context":{"vendorIdentifier":"00000000-0000-4000-8000-00000000000B"},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"signed_up","properties":{"backupEmail":"ada@example.org","email":"ada@example.com","plan":"pro","recoveryCodes":["1234"],"verifiedAt":"1970-01-01T00:01:00.000Z"},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try sut.encode([record]).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("A redacted record leaves its sensitive properties and vendor identifier out, and an array's sensitive elements null")
    func redacted() throws {
        let sut = CollectorBatchEncoder(plan: TrackingPlan(schemas: [SignedUp.schema]), instrument: NoOpInstrument())
        var context = ServiceContext.topLevel
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!)
        // EventRecord's initializer makes a record whose sensitive values stay redacted, as a
        // delivery's redactingSensitiveValues() leaves it.
        let record = EventRecord(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), backupEmail: Sensitive("ada@example.org"), recoveryCodes: [Sensitive("1234")], verifiedAt: Sensitive(Date(timeIntervalSince1970: 60))),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil,
            context: context
        )
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"signed_up","properties":{"plan":"pro","recoveryCodes":[null]},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try sut.encode([record]).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("Through redactingSensitiveValues(), the value never reaches the body")
    func throughRedactingDestination() async throws {
        let encoder = CollectorBatchEncoder(plan: TrackingPlan(schemas: [SignedUp.schema]), instrument: NoOpInstrument())
        let sink = InMemoryDestination.unbounded()
        let sut = sink.redactingSensitiveValues()
        var record = EventRecord(
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), backupEmail: nil, recoveryCodes: [], verifiedAt: Sensitive(Date(timeIntervalSince1970: 60))),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil
        )
        record.revealsSensitiveValues = true
        let unexpected = "ada@example.com"

        await sut.receive([record])
        let delivered = sink.records
        let actual = String(decoding: try encoder.encode(delivered).body, as: UTF8.self)

        #expect(!actual.contains(unexpected))
    }
}
