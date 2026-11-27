import CollectorEncoding
import EventMacros
import Foundation
import Instrumentation
import Testing
import TrackingPlans

@Suite("CollectorBatchEncoder: properties")
struct CollectorPropertyEncodingTests {
    enum Lowercase: Refinement {
        static var constraints: [Constraint<String>] {
            get throws(InvalidConstraint) { try [.pattern("^[a-z]+$", example: "pro")] }
        }
    }

    @Event(name: "scalars")
    struct Scalars {
        var text: String
        var flag: Bool
        var count: Int
        var smallest: Int64
        var largest: UInt64
        var byte: UInt8
        var ratio: Double
        var single: Float
        var identifier: UUID
        var refined: Refined<String, Lowercase>
    }

    @Event(name: "optionals")
    struct Optionals {
        var missing: String?
        var present: Int?
        var oneElement: [String]?
        var empty: [String]?
        var nested: Int??
        var nestedNil: Int??
        var date: Date?
    }

    enum AnyDate: Refinement {
        static let constraints: [Constraint<Date>] = []
    }

    @Event(name: "dates")
    struct Dates {
        var at: Date
        var qualified: Foundation.Date
        var all: [Date]
        var refined: Refined<Date, AnyDate>
    }

    struct Money: Codable {
        var amount: Int
        var currency: String

        init(amount: Int, currency: String) {
            self.amount = amount
            self.currency = currency
        }

    }

    struct Card: Codable {
        var last4: String
        var number: Sensitive<String>

        init(last4: String, number: Sensitive<String>) {
            self.last4 = last4
            self.number = number
        }

    }

    @Event(name: "paid")
    struct Paid {
        var card: Card
    }

    @Event(name: "purchased")
    struct Purchased {
        var price: Money
        var prices: [Money]
    }

    @Event(name: "quoted")
    struct Quoted {
        var text: String
    }

    @Test("Each scalar type is the JSON value the plan's documents describe")
    func scalars() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Scalars.schema]), instrument: NoOpInstrument())
        let event = Scalars(
            text: "pro",
            flag: true,
            count: -3,
            smallest: .min,
            largest: .max,
            byte: 255,
            ratio: 0.000_01,
            single: 0.1,
            identifier: UUID(uuidString: "e621e1f8-c36c-495a-93fc-0c247a3e6e5f")!,
            refined: try Refined("abc")
        )
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"scalars","properties":{"byte":255,"count":-3,"flag":true,"identifier":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","largest":1.8446744073709552e+19,"ratio":1e-05,"refined":"abc","single":0.1,"smallest":-9223372036854775808,"text":"pro"},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("A whole Double is written without a fraction")
    func wholeDouble() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Scalars.schema]), instrument: NoOpInstrument())
        let event = Scalars(text: "", flag: false, count: 0, smallest: 0, largest: 0, byte: 0, ratio: 3, single: -2, identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, refined: try Refined("a"))
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"scalars","properties":{"byte":0,"count":0,"flag":false,"identifier":"00000000-0000-0000-0000-000000000000","largest":0,"ratio":3,"refined":"a","single":-2,"smallest":0,"text":""},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("An optional is null for nil and its value otherwise, an array of one element and a nested optional included")
    func optionals() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Optionals.schema]), instrument: NoOpInstrument())
        let event = Optionals(missing: nil, present: 4, oneElement: ["a"], empty: [], nested: .some(.some(5)), nestedNil: .some(nil), date: nil)
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"optionals","properties":{"date":null,"empty":[],"missing":null,"nested":5,"nestedNil":null,"oneElement":["a"],"present":4},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("A Date is ISO 8601 in UTC with milliseconds, alone, qualified, refined or in an array")
    func dates() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Dates.schema]), instrument: NoOpInstrument())
        let event = Dates(
            at: Date(timeIntervalSince1970: 1_795_442_607.25),
            qualified: Date(timeIntervalSinceReferenceDate: 0),
            all: [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 86_400.5)],
            refined: try Refined(Date(timeIntervalSince1970: 60))
        )
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"dates","properties":{"all":["1970-01-01T00:00:00.000Z","1970-01-02T00:00:00.500Z"],"at":"2026-11-23T14:03:27.250Z","qualified":"2001-01-01T00:00:00.000Z","refined":"1970-01-01T00:01:00.000Z"},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("A type the plan can't map is written as its encoding holds it: a map is an object")
    func unmappedType() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Purchased.schema]), instrument: NoOpInstrument())
        let event = Purchased(price: Money(amount: 1999, currency: "USD"), prices: [Money(amount: 5, currency: "EUR")])
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"purchased","properties":{"price":{"amount":1999,"currency":"USD"},"prices":[{"amount":5,"currency":"EUR"}]},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("A type the plan can't map writes a redacted sensitive member as null, and a revealed one as its value")
    func unmappedTypeWithSensitiveMember() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Paid.schema]), instrument: NoOpInstrument())
        let event = Paid(card: Card(last4: "4242", number: Sensitive("4242424242424242")))
        let redacted = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        var revealed = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, event: event, timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        revealed.revealsSensitiveValues = true
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"paid","properties":{"card":{"last4":"4242","number":null}},"timestamp":"1970-01-01T00:00:00.000Z"},{"context":{},"id":"00000000-0000-4000-8000-000000000002","isRedelivered":false,"name":"paid","properties":{"card":{"last4":"4242","number":"4242424242424242"}},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [redacted, revealed]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }

    @Test("A string escapes quotes, backslashes and control characters, and keeps other characters as they are")
    func escaping() throws {
        let sut = CollectorBatchEncoder(plan: try TrackingPlan(schemas: [Quoted.schema]), instrument: NoOpInstrument())
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: Quoted(text: "\"a\\b\"\n\t\u{01}é🎉"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = #"{"records":[{"context":{},"id":"00000000-0000-4000-8000-000000000001","isRedelivered":false,"name":"quoted","properties":{"text":"\"a\\b\"\n\t\u0001é🎉"},"timestamp":"1970-01-01T00:00:00.000Z"}]}"#

        let actual = String(decoding: try #require(sut.batch(of: [record]).body).body, as: UTF8.self)

        #expect(actual == expected)
    }
}
