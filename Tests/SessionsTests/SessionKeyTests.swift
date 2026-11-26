import Events
import Foundation
import Sessions
import Testing
import Trackers

@Suite("Sessions: the key", .timeLimit(.minutes(1)))
struct SessionKeyTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("A session's key is a UUIDv7: version nibble 7, variant bits 10")
    func versionAndVariant() async throws {
        let origin = Date(timeIntervalSince1970: 1_764_000_000.123)
        let sut = Tracker(enrichers: [.sessions()], now: { origin })
        let expectedVersion: UInt8 = 0x70
        let expectedVariant: UInt8 = 0x80

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let key = try #require(records.last?.context[SessionKey.self])
        let actualVersion = key.uuid.6 & 0xF0
        let actualVariant = key.uuid.8 & 0xC0
        #expect(actualVersion == expectedVersion)
        #expect(actualVariant == expectedVariant)
    }

    @Test("A session's key starts with its first record's timestamp in Unix milliseconds, rounded down")
    func timestamp() async throws {
        // 1,764,000,000,123.9 ms, rounded down to 1,764,000,000,123: 0x019A_B697_E87B.
        let origin = Date(timeIntervalSince1970: 1_764_000_000.1239)
        let sut = Tracker(enrichers: [.sessions()], now: { origin })
        let expected: [UInt8] = [0x01, 0x9A, 0xB6, 0x97, 0xE8, 0x7B]

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let key = try #require(records.last?.context[SessionKey.self])
        let actual = [key.uuid.0, key.uuid.1, key.uuid.2, key.uuid.3, key.uuid.4, key.uuid.5]
        #expect(actual == expected)
    }

    @Test("A session starting before 1970 has a timestamp of 0, rather than trapping")
    func beforeEpoch() async throws {
        let origin = Date(timeIntervalSince1970: -1_000)
        let sut = Tracker(enrichers: [.sessions()], now: { origin })
        let expected: [UInt8] = [0, 0, 0, 0, 0, 0]

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records: [EventRecord] = []
        for await record in sut.records {
            records.append(record)
        }
        let key = try #require(records.last?.context[SessionKey.self])
        let actual = [key.uuid.0, key.uuid.1, key.uuid.2, key.uuid.3, key.uuid.4, key.uuid.5]
        #expect(actual == expected)
    }

    @Test("Sessions that start at the same millisecond get different keys: the rest is random")
    func sameTimestampDifferentKeys() async throws {
        let origin = Date(timeIntervalSince1970: 1_764_000_000)
        let first = Tracker(enrichers: [.sessions()], now: { origin })
        let second = Tracker(enrichers: [.sessions()], now: { origin })

        first.track(Tapped(number: 1))
        second.track(Tapped(number: 1))
        await first.finish()
        await second.finish()

        var firstRecords: [EventRecord] = []
        for await record in first.records {
            firstRecords.append(record)
        }
        var secondRecords: [EventRecord] = []
        for await record in second.records {
            secondRecords.append(record)
        }
        let firstKey = try #require(firstRecords.last?.context[SessionKey.self])
        let secondKey = try #require(secondRecords.last?.context[SessionKey.self])
        let firstPrefix = [firstKey.uuid.0, firstKey.uuid.1, firstKey.uuid.2, firstKey.uuid.3, firstKey.uuid.4, firstKey.uuid.5]
        let secondPrefix = [secondKey.uuid.0, secondKey.uuid.1, secondKey.uuid.2, secondKey.uuid.3, secondKey.uuid.4, secondKey.uuid.5]
        // Bytes 8 to 15: the variant's two bits and 62 random ones, which two random draws share
        // with a chance of 2^-62.
        let firstLow = [firstKey.uuid.8, firstKey.uuid.9, firstKey.uuid.10, firstKey.uuid.11, firstKey.uuid.12, firstKey.uuid.13, firstKey.uuid.14, firstKey.uuid.15]
        let secondLow = [secondKey.uuid.8, secondKey.uuid.9, secondKey.uuid.10, secondKey.uuid.11, secondKey.uuid.12, secondKey.uuid.13, secondKey.uuid.14, secondKey.uuid.15]
        #expect(firstPrefix == secondPrefix)
        #expect(firstKey != secondKey)
        #expect(firstLow != secondLow)
    }
}
