import EventMacros
import Events
import Foundation
import JSONValues
import PropertyBased
import PropertyJSON
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("PropertyReader")
struct PropertyReaderTests {
    @Event(name: "signed_up", version: 2)
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
    }

    @Test("A record reads through its event's schema, its Sensitive value left out by default")
    func handWorked() throws {
        let sut = PropertyReader(plan: try TrackingPlan(schemas: [SignedUp.schema]))
        var record = EventRecord(event: SignedUp(plan: "pro", email: Sensitive("ada@example.com")), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        record.revealsSensitiveValues = true
        let expected: [String: JSON] = ["plan": .string("pro")]

        let actual = try sut.properties(of: record, includingSensitiveValues: false)

        #expect(actual == expected)
    }

    @Test("A Sensitive value is written only when asked for and the record reveals it", arguments: [(false, false), (false, true), (true, false), (true, true)])
    func sensitiveRule(including: Bool, reveals: Bool) throws {
        let sut = PropertyReader(plan: try TrackingPlan(schemas: [SignedUp.schema]))
        var record = EventRecord(event: SignedUp(plan: "pro", email: Sensitive("ada@example.com")), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        record.revealsSensitiveValues = reveals
        let expected: JSON? = including && reveals ? .string("ada@example.com") : nil

        let actual = try sut.properties(of: record, includingSensitiveValues: including)["email"]

        #expect(actual == expected)
    }

    @Test("A record whose event the plan doesn't have at its version throws unknownEvent with its name and version")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [])
        let sut = PropertyReader(plan: try TrackingPlan(schemas: [earlier]))
        let record = EventRecord(event: SignedUp(plan: "pro", email: Sensitive("a")), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = PropertyReadingError.unknownEvent(name: "signed_up", version: 2)

        #expect(throws: expected) {
            try sut.properties(of: record, includingSensitiveValues: false)
        }
    }

    @Test("An empty plan throws unknownEvent for every record")
    func emptyPlan() throws {
        let sut = PropertyReader(plan: try TrackingPlan(schemas: []))
        let record = EventRecord(event: SignedUp(plan: "pro", email: Sensitive("a")), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = PropertyReadingError.unknownEvent(name: "signed_up", version: 2)

        #expect(throws: expected) {
            try sut.properties(of: record, includingSensitiveValues: true)
        }
    }

    @Test("For any plan and text, the reader writes the plan property as given, and the email only when asked for and revealed", .tags(.randomized))
    func readerModel() async {
        await propertyCheck(count: 200, input: Gen.uint32().array(of: 0 ... 12), Gen.bool(), Gen.bool()) { scalars, including, reveals in
            try check(scalars: scalars, including: including, reveals: reveals)
        }

        func check(scalars: [UInt32], including: Bool, reveals: Bool) throws {
            let text = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0 % 0x11_0000) }))
            let sut = PropertyReader(plan: try TrackingPlan(schemas: [SignedUp.schema]))
            var record = EventRecord(event: SignedUp(plan: text, email: Sensitive(text)), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
            record.revealsSensitiveValues = reveals
            var expected: [String: JSON] = ["plan": .string(text)]
            if including && reveals {
                expected["email"] = .string(text)
            }

            let actual = try sut.properties(of: record, includingSensitiveValues: including)

            #expect(actual == expected)
        }
    }
}
