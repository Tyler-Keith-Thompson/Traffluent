import Events
import Foundation
import Persistence
import Testing

// Every record here has the same encoded size: the same event type, number width, call site and
// name. Each test opens a store whose bound holds a number of them (StoreKind.open(holding:)).

@Suite("RecordStore: byte bound", .timeLimit(.minutes(1)))
struct RecordStoreBoundTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    @Test("A store holding as many records as its bound allows drops the oldest for the next one, and reports it", arguments: StoreKind.all)
    func dropsOldest(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        let opened = try await kind.open(at: path, events: [Tapped.self], holding: 3) { _ = $0.append(record(0)) }
        let sut = opened.store
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 0))
        for number in 0..<3 {
            _ = sut.append(record(number))
        }
        let full = sut.byteCount

        let fourth = sut.append(record(3))

        #expect(fourth.deliveryTag != nil)
        #expect(sut.byteCount == full)
        #expect(sut.byteCount <= opened.byteBound)
        #expect(sut.pendingRecordCount == 3)
        #expect(await reports.next() == expected)
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let next = try kind.open(at: copy, events: [Tapped.self], byteBound: opened.byteBound).store
        #expect(next.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [1, 2, 3])
    }

    @Test("A record too large for an empty store is kept in memory only, with nothing written and nothing dropped", arguments: StoreKind.all)
    func tooLarge(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        let small = EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location)
        // Longer than the room a segment store leaves for a delivery mark.
        let large = EventRecord(event: Tapped(number: 0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: Events.SourceLocation(file: "A", fileID: "A", function: "a much longer function name", line: 1, column: 1))
        let sut = try await kind.open(at: path, events: [Tapped.self], holding: 1) { _ = $0.append(small) }.store
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 0))
        _ = sut.append(small)
        let kept = sut.byteCount

        let actual = sut.append(large)

        #expect(actual.deliveryTag == nil)
        #expect(sut.byteCount == kept)
        #expect(sut.pendingRecordCount == 1)
        // The small record is still kept: the next small one, which needs its room, is what drops it.
        _ = sut.append(small)
        #expect(await reports.next() == expected)
    }

    @Test("A drop report counts only records not yet delivered: one delivered before it was dropped is never reported", arguments: StoreKind.all)
    func deliveredNotReported(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        let sut = try await kind.open(at: path, events: [Tapped.self], holding: 2) { _ = $0.append(record(0)) }.store
        var reports = sut.dropReports.makeAsyncIterator()
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 1)...Date(timeIntervalSince1970: 1))
        let tag = try #require(sut.append(record(0)).deliveryTag)
        tag.acknowledger.acknowledge([tag.position])

        for number in 1..<4 {
            _ = sut.append(record(number))
        }

        #expect(await reports.next() == expected)
        #expect(sut.pendingRecordCount == 2)
    }

    @Test("Recovery drops the oldest records while the store holds more than a smaller bound, and reports them", arguments: StoreKind.all)
    func recoveryWithinBound(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
        func record(_ number: Int) -> EventRecord {
            EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location)
        }
        let earlier = try await kind.open(at: path, events: [Tapped.self], holding: 100) { _ = $0.append(record(0)) }.store
        for number in 0..<3 {
            _ = earlier.append(record(number))
        }
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let expected = DropReport.sizeBound(recordCount: 1, timestamps: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 0))

        let opened = try await kind.open(at: copy, events: [Tapped.self], holding: 2) { _ = $0.append(record(0)) }

        let sut = opened.store
        var reports = sut.dropReports.makeAsyncIterator()
        #expect(await reports.next() == expected)
        #expect(sut.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [1, 2])
        #expect(sut.pendingRecordCount == 2)
        #expect(sut.byteCount <= opened.byteBound)
        // The dropped record is gone for good: a later launch with room for it doesn't get it back.
        let later = path + "-later"
        defer { try? FileManager.default.removeItem(atPath: later) }
        try FileManager.default.copyItem(atPath: copy, toPath: later)
        let last = try kind.open(at: later, events: [Tapped.self]).store
        #expect(last.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number } == [1, 2])
    }
}

extension RecordStoreBoundTests.Tapped: BinaryCodable {
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
