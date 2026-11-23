import Benchmark
import EventMacros

@Event
struct Tapped {
    var number: Int
    var screen: String
    var coupon: String?
    var express: Bool
}

// The hand-written form the generated conformance must keep pace with: the same fields, encoded
// as BinaryCodable's documentation shows.
struct HandWrittenTapped: Event, BinaryCodable {
    var number: Int
    var screen: String
    var coupon: String?
    var express: Bool

    func encode(to encoder: inout BinaryEncoder) {
        encoder.encode(number)
        encoder.encode(screen)
        encoder.encode(coupon)
        encoder.encode(express)
    }

    init(number: Int, screen: String, coupon: String?, express: Bool) {
        self.number = number
        self.screen = screen
        self.coupon = coupon
        self.express = express
    }

    init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        number = try decoder.decode()
        screen = try decoder.decode()
        coupon = try decoder.decode()
        express = try decoder.decode()
    }
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration.metrics = [.wallClock, .mallocCountTotal]
    Benchmark.defaultConfiguration.maxDuration = .seconds(2)

    let count = 1_000
    // Built before each window, so only the coding is measured.
    let handWritten = (0 ..< count).map { HandWrittenTapped(number: $0, screen: "Checkout", coupon: $0.isMultiple(of: 3) ? "SPRING" : nil, express: $0.isMultiple(of: 2)) }
    let generated = (0 ..< count).map { Tapped(number: $0, screen: "Checkout", coupon: $0.isMultiple(of: 3) ? "SPRING" : nil, express: $0.isMultiple(of: 2)) }
    var handWrittenEncoder = BinaryEncoder()
    handWritten.forEach { $0.encode(to: &handWrittenEncoder) }
    let handWrittenBytes = handWrittenEncoder.bytes
    var generatedEncoder = BinaryEncoder()
    generated.forEach { $0.encode(to: &generatedEncoder) }
    let generatedBytes = generatedEncoder.bytes

    // MARK: encode: a thousand events into one encoder.

    Benchmark("encode: BASELINE hand-written conformance") { benchmark in
        for _ in benchmark.scaledIterations {
            var encoder = BinaryEncoder()
            for event in handWritten {
                event.encode(to: &encoder)
            }
            blackHole(encoder.bytes)
        }
    }

    Benchmark("encode: @Event conformance") { benchmark in
        for _ in benchmark.scaledIterations {
            var encoder = BinaryEncoder()
            for event in generated {
                event.encode(to: &encoder)
            }
            blackHole(encoder.bytes)
        }
    }

    // MARK: decode: a thousand events from one decoder.

    Benchmark("decode: BASELINE hand-written conformance") { benchmark in
        for _ in benchmark.scaledIterations {
            var decoder = BinaryDecoder(handWrittenBytes)
            for _ in 0 ..< count {
                blackHole(try HandWrittenTapped(from: &decoder))
            }
        }
    }

    Benchmark("decode: @Event conformance") { benchmark in
        for _ in benchmark.scaledIterations {
            var decoder = BinaryDecoder(generatedBytes)
            for _ in 0 ..< count {
                blackHole(try Tapped(from: &decoder))
            }
        }
    }
}
