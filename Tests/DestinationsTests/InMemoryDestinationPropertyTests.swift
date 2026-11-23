// Property tests against a naive reference: the records kept are the last `capacity` of every
// record received, and the batches kept split them where the received batches did, leaving out
// the empty ones.

import Destinations
import Events
import Foundation
import PropertyBased
import TraffluentTestSupport
import Testing

@Suite("InMemoryDestination: properties", .timeLimit(.minutes(1)))
struct InMemoryDestinationPropertyTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("It keeps the newest capacity records, and each kept batch holds its newest records", .tags(.randomized))
    func keepsNewest() async {
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 6).array(of: 0 ... 12), Gen.int(in: 1 ... 10)) { sizes, capacity in
            let sut = InMemoryDestination(capacity: capacity)
            let location = SourceLocation(file: "A.swift", fileID: "M/A.swift", function: "f()", line: 1, column: 1)
            var next = 0
            var received: [[Int]] = []
            for size in sizes {
                received.append(Array(next ..< next + size))
                next += size
            }
            let all = received.flatMap { $0 }
            let expectedRecords = Array(all.suffix(capacity))
            let firstKept = all.count - expectedRecords.count
            let expectedBatches = received
                .map { batch in batch.filter { $0 >= firstKept } }
                .filter { !$0.isEmpty }

            for batch in received {
                await sut.receive(batch.map { EventRecord(event: Tapped(number: $0), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: location) })
            }

            let actualRecords = sut.records.compactMap { ($0.event as? Tapped)?.number }
            let actualBatches = sut.batches.map { $0.compactMap { ($0.event as? Tapped)?.number } }
            #expect(actualRecords == expectedRecords)
            #expect(actualBatches == expectedBatches)
        }
    }
}
