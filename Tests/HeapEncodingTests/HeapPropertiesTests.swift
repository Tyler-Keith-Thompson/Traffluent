import EventMacros
import Foundation
import HeapEncoding
import Testing
import TrackingPlans

// Heap takes "a number or string" as each property's value
// (https://developers.heap.io/reference/track-1, read 2026-11-27), so everything else is made one.
@Suite("HeapBatchEncoder: properties")
struct HeapPropertiesTests {
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

    @Test("Objects and arrays are spread into a property per value, named after the path joined by '.', and a boolean is the string true or false")
    func flattened() throws {
        let plan = try TrackingPlan(schemas: [CartViewed.schema])
        let event = CartViewed(cart: Cart(size: 2, items: [Item(sku: "A-1", gift: true), Item(sku: "B-2", gift: false)]), tags: ["beta", "ios"], flags: [false, true])
        let record = EventRecord(event: event, timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let sut = try HeapBatchEncoder(appID: "12343283", plan: plan)
        let expected = #""properties":{"cart.items.0.gift":"true","cart.items.0.sku":"A-1","cart.items.1.gift":"false","cart.items.1.sku":"B-2","cart.size":2,"flags.0":"false","flags.1":"true","tags.0":"beta","tags.1":"ios"}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(String(decoding: body, as: UTF8.self).contains(expected))
    }

    @Test("A Bool property is sent as \"true\" or \"false\", not a JSON boolean")
    func booleans() throws {
        let plan = try TrackingPlan(schemas: [Toggled.schema])
        let record = EventRecord(event: Toggled(on: true, off: false), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let sut = try HeapBatchEncoder(appID: "12343283", plan: plan)
        let expected = #""properties":{"off":"false","on":"true"}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(String(decoding: body, as: UTF8.self).contains(expected))
    }

    @Test("Numbers keep their JSON type, a Date is ISO 8601, and a nil property is left out")
    func scalars() throws {
        let plan = try TrackingPlan(schemas: [Measured.schema])
        let record = EventRecord(event: Measured(count: 3, negative: -7, ratio: 0.5, note: nil, at: Date(timeIntervalSince1970: 1_796_652_207)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let sut = try HeapBatchEncoder(appID: "12343283", plan: plan)
        let expected = #""properties":{"at":"2026-12-07T14:03:27.000Z","count":3,"negative":-7,"ratio":0.5}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(String(decoding: body, as: UTF8.self).contains(expected))
    }

    @Test("An event with no property to send has no properties member")
    func noProperties() throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [Opened.schema]))
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: Opened(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = #"{"app_id":"12343283","events":[{"event":"opened","idempotency_key":"6f9619ff-8b86-d011-b42d-00c04fc964ff","identity":"6f9619ff-8b86-d011-b42d-00c04fc964ff","timestamp":"2026-11-23T14:03:27.000Z"}]}"#

        let actual = sut.requests(for: [record])

        #expect(actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) } == [expected])
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A Sensitive value is never sent, even when the record reveals it: the property is left out, and so is each element of an array of them", arguments: [true, false])
    func sensitive(reveals: Bool) throws {
        let plan = try TrackingPlan(schemas: [SignedIn.schema])
        var record = EventRecord(event: SignedIn(email: Sensitive("ada@example.com"), codes: [Sensitive("123456")], method: "password"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        record.revealsSensitiveValues = reveals
        let sut = try HeapBatchEncoder(appID: "12343283", plan: plan)
        let expected = #""properties":{"method":"password"}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(expected))
        #expect(!text.contains("ada@example.com"))
        #expect(!text.contains("123456"))
    }
}
