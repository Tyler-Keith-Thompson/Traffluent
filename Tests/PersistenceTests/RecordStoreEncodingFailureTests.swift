import Events
import Foundation
import Persistence
import Testing

@Suite("RecordStore: an event whose encoding fails", .timeLimit(.minutes(1)))
struct RecordStoreEncodingFailureTests {
    struct Failing: Error {}

    // An event whose own conformance throws, as one holding a value its encoder refuses does.
    struct Unencodable: Event, Codable {
        init() {}

        func encode(to encoder: any Encoder) throws {
            throw Failing()
        }

        init(from decoder: any Decoder) throws {}
    }

    struct Tapped: Event, Codable, Equatable {
        var number: Int
    }

    @Test("A record whose event's encode(to:) throws is kept in memory only, reported as a failed write, and the records around it are kept", arguments: StoreKind.all)
    func encodingThrows(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let timestamp = Date(timeIntervalSince1970: 7)
        let expectedReport = DropReport.writeFailed(recordCount: 1, timestamps: timestamp...timestamp)
        let expectedRecovered = [Tapped(number: 1), Tapped(number: 2)]
        do {
            let sut = try kind.open(at: path, events: [Unencodable.self, Tapped.self]).store
            _ = sut.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil))

            let actual = sut.append(EventRecord(event: Unencodable(), timestamp: timestamp, sourceLocation: nil))
            _ = sut.append(EventRecord(event: Tapped(number: 2), timestamp: Date(timeIntervalSince1970: 8), sourceLocation: nil))

            var reports = sut.dropReports.makeAsyncIterator()
            #expect(actual.deliveryTag == nil)
            #expect(await reports.next() == expectedReport)
            #expect(sut.pendingRecordCount == 2)
        }
        let reopened = try kind.open(at: path, events: [Unencodable.self, Tapped.self]).store

        let recovered = reopened.takeRecoveredRecords().compactMap { $0.event as? Tapped }

        #expect(recovered == expectedRecovered)
    }
}
