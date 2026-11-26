// @Event structs holding raw-value enums: what their conformance writes, pinned byte for byte and
// read back by an independent decoder (SwiftCBOR), what a store makes of a raw value that matches
// no case, and the enumeration each property's schema gets.

import CBOR
import EventMacros
import Foundation
import Persistence
import SwiftCBOR
import Testing

/// An enum declared outside the events, whose cases the macro can't read: CaseIterable lists them.
enum EnumTestsPriority: Int, Codable, CaseIterable {
    case low
    case high = 7
}

/// An enum declared outside the events that isn't CaseIterable: its raw type alone is known.
enum EnumTestsChannel: String, Codable {
    case email
    case push
}

@Suite("@Event: raw-value enums", .timeLimit(.minutes(1)))
struct EventMacroEnumTests {
    @Event(name: "checkout_failed")
    struct CheckoutFailed: Equatable {
        enum Reason: String, Codable {
            case paymentDeclined
            case outOfStock = "out_of_stock"
        }
        var reason: Reason
    }

    /// `CheckoutFailed` at an earlier release, whose Reason had a case since removed.
    @Event(name: "checkout_failed")
    struct CheckoutFailedWithExpired {
        enum Reason: String, Codable {
            case paymentDeclined
            case outOfStock = "out_of_stock"
            case expired
        }
        var reason: Reason
    }

    @Event(name: "ticket_opened")
    struct TicketOpened: Equatable {
        var priority: EnumTestsPriority
    }

    @Event(name: "message_sent")
    struct MessageSent {
        enum Status: UInt8, Codable {
            case queued = 1
            case sent
        }
        var channel: EnumTestsChannel
        var previous: EnumTestsPriority?
        var statuses: [Status]
        var secret: Sensitive<EnumTestsPriority>
        var note: String
        var count: Int
    }

    @Test("A String raw-value enum is written as its raw value")
    func stringRawValue() throws {
        let event = CheckoutFailed(reason: .outOfStock)
        // {"reason": "out_of_stock"}
        let expectedBytes: [UInt8] = [0xA1, 0x66] + Array("reason".utf8) + [0x6C] + Array("out_of_stock".utf8)
        let expected: SwiftCBOR.CBOR = .map([.utf8String("reason"): .utf8String("out_of_stock")])

        let bytes = try CBOREncoder().encode(event)
        let actual = try SwiftCBOR.CBOR.decode(bytes)

        #expect(bytes == expectedBytes)
        #expect(actual == expected)
    }

    @Test("An Int raw-value enum is written as its raw value")
    func integerRawValue() throws {
        let event = TicketOpened(priority: .high)
        // {"priority": 7}
        let expectedBytes: [UInt8] = [0xA1, 0x68] + Array("priority".utf8) + [0x07]
        let expected: SwiftCBOR.CBOR = .map([.utf8String("priority"): .unsignedInt(7)])

        let bytes = try CBOREncoder().encode(event)
        let actual = try SwiftCBOR.CBOR.decode(bytes)

        #expect(bytes == expectedBytes)
        #expect(actual == expected)
    }

    @Test("A store keeps an enum property and recovers the same case")
    func storeRoundTrip() throws {
        let directory = NSTemporaryDirectory() + "EventMacroEnumTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let earlier = try SegmentStore(events: [CheckoutFailed.self, TicketOpened.self], directory: .init(directory))
            _ = earlier.append(EventRecord(event: CheckoutFailed(reason: .outOfStock), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
            _ = earlier.append(EventRecord(event: TicketOpened(priority: .high), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil))
        }
        let expectedFailure = [CheckoutFailed(reason: .outOfStock)]
        let expectedTicket = [TicketOpened(priority: .high)]

        let sut = try SegmentStore(events: [CheckoutFailed.self, TicketOpened.self], directory: .init(directory))

        let recovered = sut.takeRecoveredRecords()
        #expect(recovered.compactMap { $0.event as? CheckoutFailed } == expectedFailure)
        #expect(recovered.compactMap { $0.event as? TicketOpened } == expectedTicket)
    }

    @Test("A stored raw value that matches no case now, a removed case's, can't decode: the record is dropped and reported, and the others kept")
    func removedCase() async throws {
        let directory = NSTemporaryDirectory() + "EventMacroEnumTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        do {
            let earlier = try SegmentStore(events: [CheckoutFailedWithExpired.self], directory: .init(directory))
            _ = earlier.append(EventRecord(event: CheckoutFailedWithExpired(reason: .expired), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))
            _ = earlier.append(EventRecord(event: CheckoutFailedWithExpired(reason: .paymentDeclined), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil))
        }
        let expectedReport = DropReport.undecodable(recordCount: 1)
        let expected = [CheckoutFailed(reason: .paymentDeclined)]

        let sut = try SegmentStore(events: [CheckoutFailed.self], directory: .init(directory))

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? CheckoutFailed }
        #expect(actual == expected)
        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
    }

    @Test("An enum declared inside the event lists its cases' raw values, explicit and implicit, in declaration order")
    func nestedEnumeration() throws {
        let expectedRawValues: [EventSchema.Enumeration.RawValue] = [.string("paymentDeclined"), .string("out_of_stock")]
        let expectedTypeName = "Reason"
        let expectedRawTypeName = "String"

        let actual = try #require(CheckoutFailed.schema.properties.first?.enumeration)

        #expect(actual.rawValues == expectedRawValues)
        #expect(actual.typeName == expectedTypeName)
        #expect(actual.rawTypeName == expectedRawTypeName)
    }

    @Test("A CaseIterable enum declared elsewhere lists its cases; one that isn't has no enumeration")
    func runTimeEnumeration() throws {
        let expectedPriorityValues: [EventSchema.Enumeration.RawValue] = [.integer(0), .integer(7)]
        let properties = TicketOpened.schema.properties + MessageSent.schema.properties

        let priority = try #require(properties.first { $0.name == "priority" }?.enumeration)
        let channel = try #require(properties.first { $0.name == "channel" })

        #expect(priority.rawValues == expectedPriorityValues)
        #expect(priority.rawTypeName == "Int")
        #expect(priority.typeName == "EnumTestsPriority")
        #expect(channel.enumeration == nil)
    }

    @Event(name: "shape_drawn")
    struct ShapeDrawn {
        enum Kind: String, Codable {
            case `Type`
            case `self`
            case plain
        }
        var kind: Kind
    }

    @Test("Cases named after keywords are listed by their raw values")
    func keywordCases() throws {
        let expectedRawValues: [EventSchema.Enumeration.RawValue] = [.string("Type"), .string("self"), .string("plain")]

        let actual = try #require(ShapeDrawn.schema.properties.first?.enumeration)

        #expect(actual.rawValues == expectedRawValues)
    }

    @Event(name: "build_reported")
    struct BuildReported {
        enum Listed: String, Codable, CaseIterable {
            case release
            #if DEBUG
                case debug
            #endif
        }
        enum Unlisted: String, Codable {
            case release
            #if DEBUG
                case debug
            #endif
        }
        typealias Kind = Listed
        var listed: Listed
        var unlisted: Unlisted
        var kind: Kind
    }

    @Test("An enum inside the event with a case under #if is read at run time: listed when CaseIterable, none otherwise; a typealias reads the enum it names")
    func conditionalCases() throws {
        #if DEBUG
            let expectedRawValues: [EventSchema.Enumeration.RawValue] = [.string("release"), .string("debug")]
        #else
            let expectedRawValues: [EventSchema.Enumeration.RawValue] = [.string("release")]
        #endif
        let properties = BuildReported.schema.properties

        let listed = try #require(properties[0].enumeration)
        let kind = try #require(properties[2].enumeration)

        #expect(listed.rawValues == expectedRawValues)
        #expect(properties[1].enumeration == nil)
        #expect(kind.typeName == "Listed")
        #expect(properties[2].typeName == "Kind")
    }

    @Test("An enumeration is read through an optional, an array and Sensitive, and a String or Int property has none")
    func wrappedEnumeration() throws {
        let expectedPriorityValues: [EventSchema.Enumeration.RawValue] = [.integer(0), .integer(7)]
        let expectedStatusValues: [EventSchema.Enumeration.RawValue] = [.integer(1), .integer(2)]
        let properties = Dictionary(uniqueKeysWithValues: MessageSent.schema.properties.map { ($0.name, $0.enumeration) })

        let previous = try #require(properties["previous"] ?? nil)
        let statuses = try #require(properties["statuses"] ?? nil)
        let secret = try #require(properties["secret"] ?? nil)

        #expect(previous.rawValues == expectedPriorityValues)
        #expect(statuses.rawValues == expectedStatusValues)
        #expect(statuses.rawTypeName == "UInt8")
        #expect(secret.rawValues == expectedPriorityValues)
        #expect(properties["note"] == .some(nil))
        #expect(properties["count"] == .some(nil))
    }
}
