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

    @Event(name: "dated", version: 1)
    struct Dated {
        var at: Date
        var stamp: Stamp
    }

    /// A type of the app's own, which `@Event` doesn't reach, so the CBOR package writes its date
    /// itself, as a tagged one.
    struct Stamp: Codable {
        var at: Date
    }

    @Test("A Date property of 0001-01-01T00:00:00Z, and one inside a type of the app's own, are written in the proleptic Gregorian calendar")
    func dateBeforeReform() throws {
        let sut = PropertyReader(plan: try TrackingPlan(schemas: [Dated.schema]))
        let yearOne = Date(timeIntervalSince1970: -62_135_596_800)
        let record = EventRecord(event: Dated(at: yearOne, stamp: Stamp(at: yearOne)), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected: [String: JSON] = [
            "at": .string("0001-01-01T00:00:00.000Z"),
            "stamp": .object(["at": .string("0001-01-01T00:00:00.000Z")]),
        ]

        let actual = try sut.properties(of: record, includingSensitiveValues: false)

        #expect(actual == expected)
    }

    // 2^63 milliseconds is 9,223,372,036,854,775.808 seconds, which a Double holds as
    // 9,223,372,036,854,776; the Double below it, 2 seconds earlier, is within Int64's
    // milliseconds. Both survive the trip through seconds since 2001 exactly.
    static let millisecondBoundaries: [(seconds: Double, throwing: Bool)] = [
        (0x1p63 / 1000, true), ((0x1p63 / 1000).nextDown, false), (-0x1p63 / 1000, false), ((-0x1p63 / 1000).nextDown, true),
    ]

    @Test("A Date property 2^63 milliseconds or more from 1970 either way throws unrepresentableValue naming it, and one a step of a Double inside is written", arguments: millisecondBoundaries)
    func dateBeyondMilliseconds(seconds: Double, throwing: Bool) throws {
        let sut = PropertyReader(plan: try TrackingPlan(schemas: [Dated.schema]))
        let date = Date(timeIntervalSince1970: seconds)
        let record = EventRecord(event: Dated(at: date, stamp: Stamp(at: Date(timeIntervalSince1970: 0))), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = PropertyReadingError.unrepresentableValue(event: "dated", property: "at")

        if throwing {
            #expect(throws: expected) {
                try sut.properties(of: record, includingSensitiveValues: false)
            }
        } else {
            let actual = try sut.properties(of: record, includingSensitiveValues: false)["at"]
            #expect(actual == .string(try date.iso8601Timestamp))
        }
    }

    @Test("A Date inside a type of the app's own 2^63 milliseconds from 1970 throws unrepresentableValue naming the property that holds it")
    func nestedDateBeyondMilliseconds() throws {
        let sut = PropertyReader(plan: try TrackingPlan(schemas: [Dated.schema]))
        let record = EventRecord(event: Dated(at: Date(timeIntervalSince1970: 0), stamp: Stamp(at: Date(timeIntervalSince1970: 0x1p63 / 1000))), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = PropertyReadingError.unrepresentableValue(event: "dated", property: "stamp")

        #expect(throws: expected) {
            try sut.properties(of: record, includingSensitiveValues: false)
        }
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
