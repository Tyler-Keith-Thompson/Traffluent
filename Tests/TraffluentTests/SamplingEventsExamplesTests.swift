// The examples of the "Sampling Events" article
// (Sources/Traffluent/Traffluent.docc/SamplingEvents.md), verbatim, so the article cannot drift from
// the code.

import Testing
import Traffluent

@Suite("Sampling events examples", .timeLimit(.minutes(1)))
struct SamplingEventsExamplesTests {
    struct Scrolled: Event {
        var offset: Int
    }

    @Test("Sampling")
    func sampling() async throws {
        let tracker = Tracker(
            enrichers: [.sessions()],
            samplers: [.events(of: Scrolled.self, rate: 0.1), .sessions(rate: 0.5)]
        )
        tracker.track(Scrolled(offset: 120))  // if kept, its record's context[SampleRateKey.self]?.value is 0.05
        await tracker.finish()

        for await record in tracker.records where record.event is Scrolled {
            #expect(record.context[SampleRateKey.self]?.value == 0.05)
        }
    }

    @Test("Sampling: a fixed seed and the drops")
    func samplingSeedAndDrops() async {
        let tracker = Tracker(samplers: [.events(of: Scrolled.self, rate: 0.1)], samplingSeed: 42)
        for offset in 0 ..< 100 {
            tracker.track(Scrolled(offset: offset))
        }
        await tracker.finish()
        for await report in tracker.samplingDropReports {
            print(report)  // Scrolled: 89 sampled out
            #expect(report.description == "Scrolled: 89 sampled out")
        }
    }
}
