import CBOR
import Events
import Sessions
import Testing
import Trackers
import TraffluentTestSupport

@Suite("Sessions: the events and the timeout's checks")
struct SessionEventsTests {
    @Test("A start encodes as an empty map, and decodes from one")
    func startedRoundTrip() throws {
        let expected = SessionStarted()
        let expectedBytes: [UInt8] = [0xA0]

        let bytes = try CBOREncoder().encode(expected)
        let actual = try CBORDecoder().decode(SessionStarted.self, from: bytes)

        #expect(bytes == expectedBytes)
        #expect(actual == expected)
    }

    @Test("An end encodes as a map of its duration's seconds and its attoseconds, and decodes back", arguments: [
        Duration.zero,
        .seconds(90),
        .milliseconds(1_500),
        .seconds(-3),
        Duration(secondsComponent: .max, attosecondsComponent: 999_999_999_999_999_999),
    ])
    func endedRoundTrip(duration: Duration) throws {
        let expected = SessionEnded(duration: duration)
        let reference = CBOR.map([
            .textString("seconds"): CBOR(integerLiteral: duration.components.seconds),
            .textString("attoseconds"): CBOR(integerLiteral: duration.components.attoseconds),
        ]).encode()

        let bytes = try CBOREncoder().encode(expected)
        let actual = try CBORDecoder().decode(SessionEnded.self, from: bytes)

        #expect(bytes == reference)
        #expect(actual == expected)
    }

    @Test("A map holding seconds but no attoseconds doesn't decode as an end: keyNotFound names attoseconds")
    func endedTruncated() {
        let bytes = CBOR.map([.textString("seconds"): 90]).encode()
        let expectedKey = "attoseconds"

        let error = #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(SessionEnded.self, from: bytes)
        }

        guard case .keyNotFound(let key, _) = error else {
            Issue.record("Expected keyNotFound, got \(String(describing: error))")
            return
        }
        #expect(key.stringValue == expectedKey)
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
