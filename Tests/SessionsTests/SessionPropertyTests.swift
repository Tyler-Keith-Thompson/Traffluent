import Events
import Foundation
import PropertyBased
import Sessions
import Synchronization
import Testing
import Trackers
import TraffluentTestSupport

@Suite("Sessions: against a naive model", .timeLimit(.minutes(1)))
struct SessionPropertyTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("Any run of events, with any gaps between them, makes the sessions and session events a naive model does", .tags(.randomized))
    func matchesModel() async {
        // Each gap is a whole number of seconds before the event, around a 60 second timeout.
        await propertyCheck(count: 200, input: Gen.int(in: 0 ... 120).array(of: 0 ... 30)) { gaps in
            let origin = Date(timeIntervalSinceReferenceDate: 1_000)
            var times: [Date] = []
            var time = origin
            for gap in gaps {
                time = time.addingTimeInterval(Double(gap))
                times.append(time)
            }

            // The model: a list of (event, session ordinal), sessions numbered from 0.
            var expected: [String] = []
            var session = -1
            var start = origin
            var last = origin
            for (number, time) in times.enumerated() {
                if session < 0 || time.timeIntervalSince(last) >= 60 {
                    if session >= 0 {
                        expected.append("SessionEnded(duration: \(Duration.seconds(last.timeIntervalSince(start)))) in \(session)")
                    }
                    session += 1
                    start = time
                    expected.append("SessionStarted() in \(session)")
                }
                last = time
                expected.append("Tapped(number: \(number)) in \(session)")
            }

            let stamps = Stamps(times)
            let sut = Tracker(enrichers: [.sessions(timeout: .seconds(60))], now: { stamps.next() })
            for number in times.indices {
                sut.track(Tapped(number: number))
            }
            await sut.finish()

            var ordinals: [UUID: Int] = [:]
            var actual: [String] = []
            for await record in sut.records {
                let id = try #require(record.context[SessionKey.self])
                let ordinal = ordinals[id] ?? ordinals.count
                ordinals[id] = ordinal
                actual.append("\(record.event) in \(ordinal)")
            }
            #expect(actual == expected)
        }
    }

    /// The tracking times, handed out in order to the tracker's clock: `track` reads it once per
    /// event, on the test's own task.
    final class Stamps: Sendable {
        private let times: [Date]
        private let index = Atomic(0)

        init(_ times: [Date]) {
            self.times = times
        }

        func next() -> Date {
            times[index.add(1, ordering: .relaxed).oldValue]
        }
    }
}
