// Property tests against a naive reference: which version each record of any batch is read at,
// for any set of versions the decoder has a type of and the plan a schema of.

import CollectorEncoding
import EventMacros
import Foundation
import Generators
import Instrumentation
import PropertyBased
import Sampling
import Testing
import TrackingPlans
import TraffluentTestSupport

// Private: its events share one name at several versions, and other names of this test target,
// and @Event leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("CollectorBatchDecoder: the version of any record", .timeLimit(.minutes(1)))
private struct CollectorEventVersionPropertyTests {
    // One shape at every version, so a record fits whichever version it is read at, and only the
    // type it decodes into tells which.
    @Event(name: "counted")
    struct CountedAtOne {
        var count: Int
    }

    @Event(name: "counted", version: 2)
    struct CountedAtTwo {
        var count: Int
    }

    @Event(name: "counted", version: 3)
    struct CountedAtThree {
        var count: Int
    }

    @Test("Any record is read at its stated version, or without one at 1 or else the lowest readable, and reported as unknownVersion when that isn't readable", .tags(.randomized))
    func statedAndUnstatedVersions() async throws {
        await propertyCheck(count: 300, input: Gen.uint64(in: .min ... .max)) { seed in
            try check(seed: seed)
        }

        func check(seed: UInt64) throws {
            var random = Xoshiro256StarStar(seed: seed)
            let types: [any (Event & Codable).Type] = [CountedAtOne.self, CountedAtTwo.self, CountedAtThree.self]
            let schemas = [CountedAtOne.schema, CountedAtTwo.schema, CountedAtThree.schema]
            let typed = types.filter { _ in random.bernoulli(0.7) }
            let planned = schemas.filter { _ in random.bernoulli(0.7) }
            let plan = try TrackingPlan(schemas: planned)
            let sut = try CollectorBatchDecoder(plan: plan, events: typed, instrument: NoOpInstrument())
            // The naive reference: the versions both hold, and the version each record is read at.
            let readable = Set(typed.map { $0.schemaVersion }).intersection(planned.map(\.version))
            let unstated = readable.contains(1) ? 1 : readable.min() ?? 1
            let stated: [Int?] = (0 ..< random.integer(in: 0 ... 8)).map { _ in
                random.bernoulli(0.3) ? nil : random.integer(in: -1 ... 4)
            }
            let records = stated.enumerated().map { offset, version in
                let member = version.map { #","version":"# + String($0) } ?? ""
                return #"{"context":{},"id":"00000000-0000-4000-8000-"# + String(format: "%012d", offset) + #"","isRedelivered":false,"name":"counted","properties":{"count":"# + String(offset) + #"},"timestamp":"1970-01-01T00:00:00.000Z""# + member + "}"
            }
            let body = Data((#"{"records":["# + records.joined(separator: ",") + "]}").utf8)
            let read = stated.map { $0 ?? unstated }
            let expectedVersions = read.filter(readable.contains)
            // With no type of the name at all, the event is unknown, whatever the version.
            let expectedUndecoded = read.enumerated().filter { !readable.contains($0.element) }.map { offset, version in
                UndecodedRecord(
                    offset: offset,
                    recordID: UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012d", offset)),
                    eventName: "counted",
                    reason: typed.isEmpty ? .unknownEvent(name: "counted") : .unknownVersion(name: "counted", version: version)
                )
            }

            let actual = try sut.batch(from: body)

            #expect(actual.records.map { type(of: $0.event).schemaVersion } == expectedVersions)
            #expect(actual.undecodedRecords == expectedUndecoded)
        }
    }
}
