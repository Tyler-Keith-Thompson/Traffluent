// Property tests: a tracker's samplers keep exactly what a naive model drawing from the same
// SwiftPRNG streams keeps, and over many seeds keep about the fraction their rate says.

import Events
import Foundation
import Generators
import Instrumentation
import PropertyBased
import Sampling
import SeedTrees
import Testing
import Trackers
import TraffluentTestSupport

@Suite("Sampling: properties", .timeLimit(.minutes(1)))
struct SamplingPropertyTests {
    struct Scrolled: Event {
        var number: Int
    }

    struct Tapped: Event {
        var number: Int
    }

    enum CohortKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Any run of events keeps exactly what a model of an event sampler's stream and a group sampler's nodes keeps", .tags(.randomized))
    func matchesModel() async {
        // Each operation is a number from 0 to 7: 0-3 track a Scrolled in cohort 0-3, 4-7 a Tapped.
        await propertyCheck(count: 200, input: Gen.int(in: 0 ... 7).array(of: 0 ... 60), Gen.uint64(), Gen.int(in: 0 ... 10).array(of: 3)) {
            operations, seed, tenths in
            let scrolledRate = Double(tenths[0]) / 10
            let cohortRate = Double(tenths[1]) / 10
            let everyRate = Double(tenths[2]) / 10

            // The model: sampler 0 draws once per Scrolled from its node's xoshiro256** stream;
            // sampler 1 decides each cohort by its node's child named after it, for every event;
            // sampler 2 draws once per event from its own stream, whatever the others decided.
            let tree = SeedTree(seed)
            var stream = tree[0].generator(Xoshiro256StarStar.self)
            var everyStream = tree[2].generator(Xoshiro256StarStar.self)
            var expected: [String] = []
            var expectedDropped = 0
            for (number, operation) in operations.enumerated() {
                let cohort = "cohort \(operation % 4)"
                let isScrolled = operation < 4
                let scrolledKept = isScrolled ? stream.bernoulli(scrolledRate) : true
                let cohortKept = tree[1, cohort].bernoulli(cohortRate)
                let everyKept = everyStream.bernoulli(everyRate)
                if scrolledKept && cohortKept && everyKept {
                    let rate = (isScrolled ? scrolledRate * cohortRate : cohortRate) * everyRate
                    expected.append("\(number) \(cohort) \(rate)")
                } else {
                    expectedDropped += 1
                }
            }

            let sut = Tracker(samplers: [.events(of: Scrolled.self, rate: SampleRate(scrolledRate)), .grouped(by: CohortKey.self, rate: SampleRate(cohortRate)), .events(where: { _ in true }, rate: SampleRate(everyRate))], samplingSeed: seed)
            for (number, operation) in operations.enumerated() {
                var context = ServiceContext.topLevel
                context[CohortKey.self] = "cohort \(operation % 4)"
                ServiceContext.withValue(context) {
                    if operation < 4 {
                        sut.track(Scrolled(number: number))
                    } else {
                        sut.track(Tapped(number: number))
                    }
                }
            }
            await sut.finish()

            var actual: [String] = []
            for await record in sut.records {
                let number = (record.event as? Scrolled)?.number ?? (record.event as? Tapped)?.number ?? -1
                actual.append("\(number) \(record.context[CohortKey.self] ?? "none") \(record.context[SampleRateKey.self]?.value ?? -1)")
            }
            var actualDropped = 0
            for await report in sut.samplingDropReports {
                actualDropped += report.recordCount
            }
            #expect(actual == expected, "seed \(seed)")
            #expect(actualDropped == expectedDropped, "seed \(seed)")
        }
    }

    @Test("Over any seed, an event sampler at 0.3 keeps about 30% of 1,000 events: within six standard deviations", .tags(.randomized))
    func eventFraction() async {
        await propertyCheck(count: 50, input: Gen.uint64()) { seed in
            let sut = Tracker(samplers: [.events(of: Scrolled.self, rate: 0.3)], samplingSeed: seed)
            // n p = 300, sqrt(n p (1 - p)) is about 14.5, so six deviations are 87.
            let expected = 213 ... 387

            for number in 0 ..< 1_000 {
                sut.track(Scrolled(number: number))
            }
            await sut.finish()

            var actual = 0
            for await _ in sut.records {
                actual += 1
            }
            #expect(expected.contains(actual), "seed \(seed)")
        }
    }

    @Test("Over any seed, a group sampler at 0.3 keeps about 30% of 1,000 groups: within six standard deviations", .tags(.randomized))
    func groupFraction() async {
        await propertyCheck(count: 50, input: Gen.uint64()) { seed in
            let sut = Tracker(samplers: [.grouped(by: CohortKey.self, rate: 0.3)], samplingSeed: seed)
            let expected = 213 ... 387

            for number in 0 ..< 1_000 {
                var context = ServiceContext.topLevel
                context[CohortKey.self] = "cohort \(number)"
                ServiceContext.withValue(context) {
                    sut.track(Tapped(number: number))
                }
            }
            await sut.finish()

            var actual = 0
            for await _ in sut.records {
                actual += 1
            }
            #expect(expected.contains(actual), "seed \(seed)")
        }
    }
}
