import Events
import Foundation
import Persistence
import Testing

// Each test ends with a record the bound makes room for by dropping the one before it: that
// sizeBound report comes after every report the earlier appends made, so the test reads up to it
// and knows no other report came first.

@Suite("RecordStore: event types not in events", .timeLimit(.minutes(1)))
struct RecordStoreUnlistedEventTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    struct Scrolled: Event, Equatable {
        var number: Int
    }

    struct Swiped: Event, Equatable {
        var number: Int
    }

    @Test("Records of a type not in events are kept in memory only, and each such type is reported once, on its first record", arguments: StoreKind.all)
    func reportedOncePerType(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ event: any Event, _ number: Int) -> EventRecord {
            EventRecord(event: event, timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        let sut = try await kind.open(at: path, events: [Tapped.self], holding: 1) { _ = $0.append(record(Tapped(number: 0), 0)) }.store
        var reports = sut.dropReports.makeAsyncIterator()
        let expected: [DropReport] = [
            .notPersisted(event: "Scrolled"),
            .notPersisted(event: "Swiped"),
            .sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1)...Date(timeIntervalSince1970: 1)),
        ]
        let expectedWritten = [false, true, false, false, false, false, true]

        let kept = [
            sut.append(record(Scrolled(number: 0), 0)),
            sut.append(record(Tapped(number: 1), 1)),
            sut.append(record(Scrolled(number: 2), 2)),
            sut.append(record(Swiped(number: 3), 3)),
            sut.append(record(Scrolled(number: 4), 4)),
            sut.append(record(Swiped(number: 5), 5)),
            sut.append(record(Tapped(number: 6), 6)),
        ]

        var actual: [DropReport] = []
        for _ in expected {
            if let report = await reports.next() {
                actual.append(report)
            }
        }
        #expect(actual == expected)
        #expect(kept.map { $0.deliveryTag != nil } == expectedWritten)
    }

    @Test("Records of types in events produce no notPersisted report", arguments: StoreKind.all)
    func listedTypesNotReported(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        // Sized on a Scrolled record, as both appends below are: a Tapped one is smaller.
        let sut = try await kind.open(at: path, events: [Tapped.self, Scrolled.self], holding: 1) { store in
            _ = store.append(EventRecord(event: Scrolled(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        }.store
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1)...Date(timeIntervalSince1970: 1))

        _ = sut.append(EventRecord(event: Scrolled(number: 0), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))
        _ = sut.append(EventRecord(event: Scrolled(number: 1), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: location))

        // The first report is the Scrolled record the bound dropped: neither listed type made one.
        let actual = await reports.next()
        #expect(actual == expected)
    }

    @Test("A store opened again reports an unlisted type again, on its first record in that run", arguments: StoreKind.all)
    func reportedAgainInANewStore(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let earlier = try kind.open(at: path, events: [Tapped.self]).store
        var earlierReports = earlier.dropReports.makeAsyncIterator()
        _ = earlier.append(EventRecord(event: Swiped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location))
        let expected = DropReport.notPersisted(event: "Swiped")
        let first = await earlierReports.next()
        let later = path + "-later"
        defer { try? FileManager.default.removeItem(atPath: later) }
        let sut = try kind.open(at: later, events: [Tapped.self]).store
        var reports = sut.dropReports.makeAsyncIterator()

        _ = sut.append(EventRecord(event: Swiped(number: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: location))

        let actual = await reports.next()
        #expect(first == expected)
        #expect(actual == expected)
    }
}

extension RecordStoreUnlistedEventTests.Tapped: BinaryCodable {
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

extension RecordStoreUnlistedEventTests.Scrolled: BinaryCodable {
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
