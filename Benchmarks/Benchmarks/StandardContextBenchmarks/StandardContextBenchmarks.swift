import Benchmark
import Events
import Foundation
import StandardContext
import Trackers

struct Tapped: Event {
    var number: Int
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration.metrics = [.wallClock, .mallocCountTotal]
    Benchmark.defaultConfiguration.maxDuration = .seconds(2)

    let tracks = 1_000
    let application = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")

    // MARK: enrich: a thousand events tracked and enriched, through the tracker's worker.
    //
    // Nothing public runs an enricher outside a tracker, so each event goes through one, and the
    // window takes in `finish()`, which waits for the worker to enrich every record. The worker
    // runs on a dispatch queue, which the simulated instruction counts don't see: judge the
    // enrichment by the malloc counts, which count every thread, and by wall clock (`just bench`).

    // The hand-written form a standard enricher must keep pace with: a struct read once, kept,
    // and set on each record's context.
    Benchmark("enrich: BASELINE a hand-written enricher setting a stored struct", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let tracker = Tracker(enrichers: [Enricher { $0[ApplicationKey.self] = application }])
        benchmark.startMeasurement()
        for number in 0 ..< tracks {
            tracker.track(Tapped(number: number))
        }
        await tracker.finish()
        benchmark.stopMeasurement()
    }

    // Off Apple platforms, where the simulated counts are taken, the device's default is none, so
    // `device` is given the value an iPhone reads; `network()` has no monitor there and sets nothing.
    for (name, enricher) in [
        ("application()", Enricher.application()),
        ("device()", Enricher.device(DeviceKey.Value(model: "iPhone17,1", formFactor: .phone))),
        ("operatingSystem()", Enricher.operatingSystem()),
        ("locale()", Enricher.locale()),
        ("network()", Enricher.network()),
    ] {
        Benchmark("enrich: \(name)", configuration: .init(scalingFactor: .kilo)) { benchmark in
            let tracker = Tracker(enrichers: [enricher])
            benchmark.startMeasurement()
            for number in 0 ..< tracks {
                tracker.track(Tapped(number: number))
            }
            await tracker.finish()
            benchmark.stopMeasurement()
        }
    }

    // MARK: make: the platform read once, as each enricher is made, rather than for every event.

    Benchmark("make: application() from the main bundle") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(Enricher.application())
        }
    }

    Benchmark("make: operatingSystem() from ProcessInfo") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(Enricher.operatingSystem())
        }
    }

    Benchmark("make: locale() from Locale.current") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(Enricher.locale())
        }
    }
}
