// The example of the Events module's landing article
// (Sources/Events/Events.docc/Events.md), verbatim, so the article cannot drift from the code.

import Foundation
import Testing
import Traffluent

@Suite("Events module examples", .timeLimit(.minutes(1)))
struct EventsModuleExamplesTests {
    enum PlanName: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.minLength(1), .maxLength(32)] }
        }
    }

    @Event(consent: .functional)
    struct SignedUp {
        var plan: Refined<String, PlanName>
        var email: Sensitive<String>
    }

    @Test("An event, its record and a refined value")
    func eventAndRecord() throws {
        let event = SignedUp(plan: try Refined("pro"), email: Sensitive("ada@example.com"))
        let record = EventRecord(event: event, timestamp: .now, sourceLocation: nil)
        let name = record.name  // "SignedUp"
        let email = record.reveal(event.email)  // nil: a record made by hand keeps its sensitive values redacted
        let empty = try? Refined<String, PlanName>("")  // nil: it throws UnsatisfiedConstraint.minLength

        let expectedName = "SignedUp"
        let expectedCategory = ConsentCategory.functional
        #expect(name == expectedName)
        #expect(record.consentCategory == expectedCategory)
        #expect(email == nil)
        #expect(empty == nil)
        #expect(throws: UnsatisfiedConstraint.minLength) {
            try Refined<String, PlanName>("")
        }
    }
}
