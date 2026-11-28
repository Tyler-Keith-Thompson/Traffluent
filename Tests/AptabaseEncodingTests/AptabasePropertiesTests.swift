import AptabaseEncoding
import EventMacros
import Foundation
import Testing
import TrackingPlans

// Aptabase stores a number as a numeric property, a string as a string one, true and false as the
// strings "true" and "false", an array as "[Array]", an object as "{Object}" and null as ""
// (github.com/aptabase/aptabase at 89d36185, EventBody.SplitProps, read 2026-11-27), so objects
// and arrays are flattened and nulls left out.
// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("AptabaseBatchEncoder: properties")
private struct AptabasePropertiesTests {
    struct Item: Codable, Hashable {
        var sku: String
        var gift: Bool
    }

    struct Cart: Codable, Hashable {
        var size: Int
        var items: [Item]
    }

    @Event(name: "cart_viewed")
    struct CartViewed {
        var cart: Cart
        var tags: [String]
        var flags: [Bool]
    }

    @Event(name: "toggled")
    struct Toggled {
        var on: Bool
        var off: Bool
    }

    @Event(name: "measured")
    struct Measured {
        var count: Int
        var negative: Int
        var ratio: Double
        var note: String?
        var at: Date
    }

    @Event(name: "opened")
    struct Opened {}

    @Event(name: "signed_in")
    struct SignedIn {
        var email: Sensitive<String>
        var codes: [Sensitive<String>]
        var method: String
    }

    @Test("Objects and arrays are spread into a property per value, named after the path joined by '.'")
    func flattened() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let plan = try TrackingPlan(schemas: [CartViewed.schema])
        let event = CartViewed(cart: Cart(size: 2, items: [Item(sku: "A-1", gift: true), Item(sku: "B-2", gift: false)]), tags: ["beta", "ios"], flags: [false, true])
        let record = EventRecord(event: event, timestamp: tracked, sourceLocation: nil)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: plan, now: { tracked })
        let expected = #""props":{"cart.items.0.gift":true,"cart.items.0.sku":"A-1","cart.items.1.gift":false,"cart.items.1.sku":"B-2","cart.size":2,"flags.0":false,"flags.1":true,"tags.0":"beta","tags.1":"ios"}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(String(decoding: body, as: UTF8.self).contains(expected))
    }

    @Test("A Bool property is sent as a JSON boolean, which Aptabase stores as true or false, as its SDKs send it")
    func booleans() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let plan = try TrackingPlan(schemas: [Toggled.schema])
        let record = EventRecord(event: Toggled(on: true, off: false), timestamp: tracked, sourceLocation: nil)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: plan, now: { tracked })
        let expected = #""props":{"off":false,"on":true}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(String(decoding: body, as: UTF8.self).contains(expected))
    }

    @Test("Numbers keep their JSON type, a Date is ISO 8601, and a nil property is left out")
    func scalars() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let plan = try TrackingPlan(schemas: [Measured.schema])
        let record = EventRecord(event: Measured(count: 3, negative: -7, ratio: 0.5, note: nil, at: Date(timeIntervalSince1970: 1_796_652_207)), timestamp: tracked, sourceLocation: nil)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: plan, now: { tracked })
        let expected = #""props":{"at":"2026-12-07T14:03:27.000Z","count":3,"negative":-7,"ratio":0.5}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(String(decoding: body, as: UTF8.self).contains(expected))
    }

    @Test("An event with no property to send has no props member")
    func noProperties() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: true, plan: try TrackingPlan(schemas: [Opened.schema]), now: { tracked })
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: Opened(), timestamp: tracked, sourceLocation: nil)
        let expected = #"[{"eventName":"opened","sessionId":"6f9619ff-8b86-d011-b42d-00c04fc964ff","systemProps":{"isDebug":true,"sdkVersion":"Traffluent"},"timestamp":"2026-11-23T14:03:27.000Z"}]"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A Sensitive value is never sent, even when the record reveals it: the property is left out, and so is each element of an array of them", arguments: [true, false])
    func sensitive(reveals: Bool) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let plan = try TrackingPlan(schemas: [SignedIn.schema])
        var record = EventRecord(event: SignedIn(email: Sensitive("ada@example.com"), codes: [Sensitive("123456")], method: "password"), timestamp: tracked, sourceLocation: nil)
        record.revealsSensitiveValues = reveals
        let sut = AptabaseBatchEncoder(isDebug: false, plan: plan, now: { tracked })
        let expected = #""props":{"method":"password"}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(expected))
        #expect(!text.contains("ada@example.com"))
        #expect(!text.contains("123456"))
    }
}
