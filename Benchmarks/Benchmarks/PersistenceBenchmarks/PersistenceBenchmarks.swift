import Benchmark
import Events
import Foundation
import Persistence
import Trackers

struct Tapped: Event {
    var number: Int
    var screen: String
}

extension Tapped: BinaryCodable {
    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
        encoder.encode(screen)
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
        screen = try decoder.decode()
    }
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration.metrics = [.wallClock, .mallocCountTotal]
    Benchmark.defaultConfiguration.maxDuration = .seconds(2)

    let tracks = 1_000
    // About the size of a tracked Tapped record's frame.
    let frame = [UInt8](repeating: 0x2A, count: 112)

    // MARK: track: the cost of one tracked event, written through to disk.

    // The hand-written form the library must keep pace with: one write() of a record-sized frame
    // to a file opened for appending, per event.
    Benchmark("track: BASELINE raw write()", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let descriptor = open(directory + "/raw", O_WRONLY | O_CREAT | O_APPEND, 0o600)
        defer { close(descriptor) }
        benchmark.startMeasurement()
        for _ in 0 ..< tracks {
            blackHole(frame.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) })
        }
        benchmark.stopMeasurement()
    }

    Benchmark("track: Tracker(store:) with a SegmentStore", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let tracker = Tracker(store: try SegmentStore(events: [Tapped.self], directory: .init(directory)))
        benchmark.startMeasurement()
        for number in 0 ..< tracks {
            tracker.track(Tapped(number: number, screen: "Checkout"))
        }
        benchmark.stopMeasurement()
        blackHole(tracker)
    }

    // The same tracking with no store: what write-through adds to it.
    Benchmark("track: Tracker() in memory only", configuration: .init(scalingFactor: .kilo)) { benchmark in
        let tracker = Tracker()
        benchmark.startMeasurement()
        for number in 0 ..< tracks {
            tracker.track(Tapped(number: number, screen: "Checkout"))
        }
        benchmark.stopMeasurement()
        blackHole(tracker)
    }
}

/// A new, empty directory for one run's files.
func scratchDirectory() -> String {
    let path = NSTemporaryDirectory() + "PersistenceBenchmarks-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}
