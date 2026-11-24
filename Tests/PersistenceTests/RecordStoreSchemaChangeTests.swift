import Events
import Foundation
import Persistence
import Testing

// A store is written with one version of an event type and reopened with another of the same name,
// as an app update that changes the event's properties finds the records the earlier release left.

@Suite("RecordStore: schema changes", .timeLimit(.minutes(1)))
struct RecordStoreSchemaChangeTests {
    struct Original: Event, Equatable {
        static let name = "Tapped"
        var number: Int
        var label: String
    }

    struct WithCoupon: Event, Equatable {
        static let name = "Tapped"
        var number: Int
        var label: String
        var coupon: String?
    }

    struct WithoutLabel: Event, Equatable {
        static let name = "Tapped"
        var number: Int
    }

    struct Reordered: Event, Equatable {
        static let name = "Tapped"
        var label: String
        var number: Int
    }

    struct WithSeats: Event, Equatable {
        static let name = "Tapped"
        var number: Int
        var label: String
        var seats: Int
    }

    /// An event of another type, which every version decodes.
    struct Marker: Event, Equatable {
        var number: Int
    }

    struct Retyped: Event, Equatable {
        static let name = "Tapped"
        var number: String
        var label: String
    }

    struct WithCurrency: Event, Equatable {
        static let name = "Tapped"
        var number: Int
        var label: String
        var currency: String = "USD"
    }

    /// `Original` with its version raised and its shape kept.
    struct OriginalVersion2: Event, Equatable {
        static let name = "Tapped"
        static let schemaVersion = 2
        var number: Int
        var label: String
    }

    /// Another event, "Swiped", at two versions.
    struct Swiped: Event, Equatable {
        var number: Int
    }

    struct SwipedVersion3: Event, Equatable {
        static let name = "Swiped"
        static let schemaVersion = 3
        var number: Int
    }

    @Test("A record stored before an optional property was added decodes with it nil", arguments: StoreKind.all)
    func optionalAdded(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try kind.open(at: path, events: [Original.self]).store
            _ = earlier.append(EventRecord(event: Original(number: 3, label: "Checkout"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expected = [WithCoupon(number: 3, label: "Checkout", coupon: nil)]

        let sut = try kind.open(at: path, events: [WithCoupon.self]).store

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? WithCoupon }
        #expect(actual == expected)
    }

    @Test("A record stored before a property was removed decodes with the rest intact", arguments: StoreKind.all)
    func propertyRemoved(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try kind.open(at: path, events: [Original.self]).store
            _ = earlier.append(EventRecord(event: Original(number: 3, label: "Checkout"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expected = [WithoutLabel(number: 3)]

        let sut = try kind.open(at: path, events: [WithoutLabel.self]).store

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? WithoutLabel }
        #expect(actual == expected)
    }

    @Test("A record stored before its properties were reordered decodes each by its name", arguments: StoreKind.all)
    func reordered(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try kind.open(at: path, events: [Original.self]).store
            _ = earlier.append(EventRecord(event: Original(number: 3, label: "Checkout"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expected = [Reordered(label: "Checkout", number: 3)]

        let sut = try kind.open(at: path, events: [Reordered.self]).store

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? Reordered }
        #expect(actual == expected)
    }

    @Test("A record stored before a property with a default value was added decodes with the default", arguments: StoreKind.all)
    func defaultedAdded(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try kind.open(at: path, events: [Original.self]).store
            _ = earlier.append(EventRecord(event: Original(number: 3, label: "Checkout"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expected = [WithCurrency(number: 3, label: "Checkout", currency: "USD")]

        let sut = try kind.open(at: path, events: [WithCurrency.self]).store

        let actual = sut.takeRecoveredRecords().compactMap { $0.event as? WithCurrency }
        #expect(actual == expected)
    }

    @Test("Records stored at another version than their type's are dropped unread, one report per event and stored version, by name; the rest are kept", arguments: StoreKind.all)
    func versionMismatch(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try kind.open(at: path, events: [Swiped.self, Original.self, Marker.self]).store
            _ = earlier.append(EventRecord(event: Swiped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Original(number: 2, label: "Old"), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Marker(number: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Original(number: 4, label: "Old"), timestamp: Date(timeIntervalSince1970: 3), sourceLocation: location))
        }
        let expectedReports: [DropReport] = [
            .versionMismatch(event: "Swiped", storedVersion: 1, currentVersion: 3, recordCount: 1),
            .versionMismatch(event: "Tapped", storedVersion: 1, currentVersion: 2, recordCount: 2),
        ]
        let expected = [Marker(number: 3)]

        let sut = try kind.open(at: path, events: [OriginalVersion2.self, SwipedVersion3.self, Marker.self]).store

        let recovered = sut.takeRecoveredRecords()
        let actual = recovered.compactMap { $0.event as? Marker }
        #expect(recovered.count == expected.count)
        #expect(actual == expected)
        var reports = sut.dropReports.makeAsyncIterator()
        var actualReports: [DropReport] = []
        for _ in expectedReports {
            if let report = await reports.next() { actualReports.append(report) }
        }
        #expect(actualReports == expectedReports)
        #expect(sut.pendingRecordCount == expected.count)
    }

    @Test("A record stored before a required property was added can't decode: it is dropped and reported, and the records that decode are kept", arguments: StoreKind.all)
    func requiredAdded(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try kind.open(at: path, events: [Original.self, Marker.self]).store
            _ = earlier.append(EventRecord(event: Original(number: 1, label: "Old"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
            _ = earlier.append(EventRecord(event: Marker(number: 2), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
        }
        let expectedReport = DropReport.undecodable(recordCount: 1)
        let expected = [Marker(number: 2)]

        let sut = try kind.open(at: path, events: [WithSeats.self, Marker.self]).store

        let recovered = sut.takeRecoveredRecords()
        let actual = recovered.compactMap { $0.event as? Marker }
        #expect(recovered.count == expected.count)
        #expect(actual == expected)
        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expectedReport)
    }

    @Test("A record whose property's type changed since it was stored can't decode: it is dropped, reported and forgotten", arguments: StoreKind.all)
    func typeChanged(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        do {
            let earlier = try kind.open(at: path, events: [Original.self]).store
            _ = earlier.append(EventRecord(event: Original(number: 3, label: "Checkout"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }
        let expected = DropReport.undecodable(recordCount: 1)

        let sut = try kind.open(at: path, events: [Retyped.self]).store

        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().isEmpty)
        #expect(sut.pendingRecordCount == 0)
    }
}

extension RecordStoreSchemaChangeTests.Original: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
            map.encode(label, forKey: "label")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
        label = try map.decode(forKey: "label")
    }
}

extension RecordStoreSchemaChangeTests.WithCoupon: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
            map.encode(label, forKey: "label")
            map.encode(coupon, forKey: "coupon")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
        label = try map.decode(forKey: "label")
        coupon = try map.decode(forKey: "coupon")
    }
}

extension RecordStoreSchemaChangeTests.WithoutLabel: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
    }
}

extension RecordStoreSchemaChangeTests.Reordered: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(label, forKey: "label")
            map.encode(number, forKey: "number")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        label = try map.decode(forKey: "label")
        number = try map.decode(forKey: "number")
    }
}

extension RecordStoreSchemaChangeTests.WithSeats: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
            map.encode(label, forKey: "label")
            map.encode(seats, forKey: "seats")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
        label = try map.decode(forKey: "label")
        seats = try map.decode(forKey: "seats")
    }
}

extension RecordStoreSchemaChangeTests.Retyped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
            map.encode(label, forKey: "label")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
        label = try map.decode(forKey: "label")
    }
}

extension RecordStoreSchemaChangeTests.WithCurrency: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
            map.encode(label, forKey: "label")
            map.encode(currency, forKey: "currency")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
        label = try map.decode(forKey: "label")
        currency = try map.decode(forKey: "currency", default: "USD")
    }
}

extension RecordStoreSchemaChangeTests.OriginalVersion2: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
            map.encode(label, forKey: "label")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
        label = try map.decode(forKey: "label")
    }
}

extension RecordStoreSchemaChangeTests.Swiped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
    }
}

extension RecordStoreSchemaChangeTests.SwipedVersion3: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
    }
}

extension RecordStoreSchemaChangeTests.Marker: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(number, forKey: "number")
        }
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        number = try map.decode(forKey: "number")
    }
}
