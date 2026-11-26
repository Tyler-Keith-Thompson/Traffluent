import Events
import Persistence
import Sessions
import Testing
import Trackers
import TraffluentTestSupport

@Suite("Sessions: the events and the timeout's checks")
struct SessionEventsTests {
    @Test("A start encodes as an empty map, and decodes from one")
    func startedRoundTrip() throws {
        let expected = SessionStarted()
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try SessionStarted(from: &decoder)

        #expect(encoder.bytes == [0xA0])
        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("An end encodes as a map of its duration's seconds, then its attoseconds, and decodes back", arguments: [
        Duration.zero,
        .seconds(90),
        .milliseconds(1_500),
        .seconds(-3),
        Duration(secondsComponent: .max, attosecondsComponent: 999_999_999_999_999_999),
    ])
    func endedRoundTrip(duration: Duration) throws {
        let expected = SessionEnded(duration: duration)
        var reference = BinaryEncoder()
        reference.encodeMap { map in
            map.encode(duration.components.seconds, forKey: "seconds")
            map.encode(duration.components.attoseconds, forKey: "attoseconds")
        }
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try SessionEnded(from: &decoder)

        #expect(encoder.bytes == reference.bytes)
        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("A map holding seconds but no attoseconds doesn't decode as an end")
    func endedTruncated() {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode(Int64(90), forKey: "seconds")
        }
        var decoder = BinaryDecoder(encoder.bytes)

        #expect(throws: BinaryDecodingError.keyNotFound) {
            try SessionEnded(from: &decoder)
        }
    }

    @Test("The events' schemas name them, at version 1, for analytics, an end with its duration")
    func schemas() {
        let expectedStarted = EventSchema(name: "SessionStarted", version: 1, consentCategory: .analytics, properties: [])
        let expectedEnded = EventSchema(
            name: "SessionEnded",
            version: 1,
            consentCategory: .analytics,
            properties: [EventSchema.Property(name: "duration", typeName: "Duration", isOptional: false)]
        )

        let actualStarted = SessionStarted.schema
        let actualEnded = SessionEnded.schema

        #expect(actualStarted == expectedStarted)
        #expect(actualEnded == expectedEnded)
    }

    @Test("sessions(timeout:) throws NonPositiveSessionTimeout for a timeout of zero or less", arguments: [Duration.zero, .seconds(-1), .nanoseconds(-1)])
    func invalidTimeout(timeout: Duration) {
        #expect(throws: NonPositiveSessionTimeout()) {
            _ = try Enricher.sessions(timeout: timeout)
        }
    }

    @Test("sessions(timeout:) makes an enricher for the smallest positive timeout")
    func accepts() async throws {
        let sut = Tracker(enrichers: [try .sessions(timeout: .nanoseconds(1), kinds: [])])

        sut.track(SessionStarted())
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next())
        #expect(actual.context[SessionKey.self] != nil)
    }
}
