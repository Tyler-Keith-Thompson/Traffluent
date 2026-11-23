// Property tests against a naive reference: a log is a queue of the records not yet delivered,
// bounded in bytes. Whatever is appended, acknowledged and dropped, every record is acknowledged,
// recovered by the next store, or counted in a drop report, and the log never passes its bound.

import Events
import Foundation
import Persistence
import PropertyBased
import SystemPackage
import Testing
import TraffluentTestSupport

@Suite("SegmentStore: properties", .timeLimit(.minutes(1)))
struct SegmentStorePropertyTests {
    struct Tapped: Event {
        var number: Int
        var label: String
    }

    @Test("No record is lost silently, and the log never passes its bound", .tags(.randomized))
    func noSilentLoss() async {
        await propertyCheck(
            count: 60,
            input: Gen.int(in: 0...40), Gen.int(in: 120...900), Gen.int(in: 40...400), Gen.uint8().array(of: 0...40)
        ) { appendCount, bound, segment, choices in
            let directory = FilePath(NSTemporaryDirectory()).appending("SegmentStorePropertyTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(atPath: directory.string) }
            let location = Events.SourceLocation(file: "A", fileID: "A", function: "f", line: 1, column: 1)
            let sut = try SegmentStore(events: [Tapped.self], directory: directory, byteBound: bound, segmentByteCount: segment)
            var tags: [DeliveryTag?] = []
            var acknowledged: Set<Int> = []
            var memoryOnly = 0

            for number in 0..<appendCount {
                let choice = Int(choices.isEmpty ? 0 : choices[number % choices.count])
                let label = String(repeating: "x", count: choice % 50)
                let record = sut.append(EventRecord(event: Tapped(number: number, label: label), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: location))
                tags.append(record.deliveryTag)
                if record.deliveryTag == nil { memoryOnly += 1 }
                #expect(sut.byteCount <= bound)
                if choice % 3 == 0, let tag = tags[number / 2] {
                    let before = sut.pendingRecordCount
                    tag.acknowledger.acknowledge([tag.position])
                    // A record the bound already dropped, or one acknowledged before, isn't pending.
                    if sut.pendingRecordCount < before {
                        acknowledged.insert(number / 2)
                    }
                }
            }
            let pending = sut.pendingRecordCount
            let next = try SegmentStore(events: [Tapped.self], directory: directory, byteBound: bound, segmentByteCount: segment)
            let recovered = next.takeRecoveredRecords().compactMap { ($0.event as? Tapped)?.number }
            // A segment comes back whole, so records acknowledged in a segment still kept come
            // back too; the ones not acknowledged are exactly those still pending.
            let unacknowledged = recovered.filter { !acknowledged.contains($0) }
            var reports = sut.dropReports.makeAsyncIterator()
            var dropped = 0
            while dropped + unacknowledged.count + acknowledged.count + memoryOnly < appendCount {
                guard case .sizeBound(let count, _) = await reports.next() else { break }
                dropped += count
            }

            #expect(unacknowledged.count == pending)
            #expect(recovered == recovered.sorted())
            #expect(dropped + unacknowledged.count + acknowledged.count + memoryOnly == appendCount)
        }
    }
}

extension SegmentStorePropertyTests.Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
        encoder.encode(label)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
        label = try decoder.decode()
    }
}
