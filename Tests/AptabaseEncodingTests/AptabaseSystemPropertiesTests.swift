import AptabaseEncoding
import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import StandardContext
import Testing
import TrackingPlans

// Aptabase's SystemProperties (github.com/aptabase/aptabase at 89d36185,
// src/Features/Ingestion/EventBody.cs, read 2026-11-27): IsDebug; OSName up to 30 characters,
// OSVersion 100, Locale 10, AppVersion 50, AppBuildNumber 20, DeviceModel 100; SdkVersion required,
// up to 40. Its model validation answers 400 for the whole request past one.
// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("AptabaseBatchEncoder: system properties")
private struct AptabaseSystemPropertiesTests {
    @Event(name: "opened")
    struct Opened {}

    @Test("The standard context is sent as systemProps: the system's name and version, the app's version and build, the device's model and the locale's language and region")
    func standardContext() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Opened.schema]), now: { tracked })
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        context[DeviceKey.self] = DeviceKey.Value(model: "MacBookPro18,3", formFactor: .mac)
        context[LocaleKey.self] = Locale(identifier: "fr_CA")
        context[NetworkKey.self] = .wifi
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "macOS", version: "26.1.0")
        let record = EventRecord(event: Opened(), timestamp: tracked, sourceLocation: nil, context: context)
        let expected = #""systemProps":{"appBuildNumber":"418","appVersion":"2.4.1","deviceModel":"MacBookPro18,3","isDebug":false,"locale":"fr-CA","osName":"macOS","osVersion":"26.1.0","sdkVersion":"Traffluent"}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(expected))
        #expect(!text.contains("wifi"))
        #expect(!text.contains("com.example.shop"))
    }

    @Test("An app's version or build its bundle doesn't give is left out, and so is each key the context has no value for")
    func partialContext() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Opened.schema]), now: { tracked })
        var context = ServiceContext.topLevel
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: "1.0", build: nil)
        let record = EventRecord(event: Opened(), timestamp: tracked, sourceLocation: nil, context: context)
        let expected = #""systemProps":{"appVersion":"1.0","isDebug":false,"sdkVersion":"Traffluent"}"#

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        #expect(String(decoding: body, as: UTF8.self).contains(expected))
    }

    @Test("isDebug is as the encoder is made, on every event", arguments: [true, false])
    func isDebug(isDebug: Bool) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: isDebug, plan: try TrackingPlan(schemas: [Opened.schema]), now: { tracked })
        let batch = (0 ..< 3).map { _ in EventRecord(event: Opened(), timestamp: tracked, sourceLocation: nil) }
        let expected = Array(repeating: isDebug, count: 3)

        let body = try #require(sut.requests(for: batch).requests.first).body.body

        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(events.map { ($0["systemProps"] as? [String: Any])?["isDebug"] as? Bool } == expected)
    }

    // Aptabase takes a locale of up to 10 characters. Every registered language and region fit,
    // so the longest are made-up languages of 7 to 11 letters, which BCP 47 allows up to 8.
    @Test("The locale is its language and region, without a script or extension, or its language alone without a region or past 10 characters with one, and left out past 10 alone", arguments: [
        ("en_US", "en-US"), ("fr", "fr"), ("zh_Hans_CN", "zh-CN"), ("th_TH@calendar=buddhist", "th-TH"), ("es_419", "es-419"), ("fil_PH", "fil-PH"),
        ("de_DE@collation=phonebook", "de-DE"), ("sr_Latn", "sr"),
        ("abcdefg_US", "abcdefg-US"), ("abcdefgh_US", "abcdefgh"), ("abcdefghij", "abcdefghij"), ("abcdefghijk", nil),
    ] as [(String, String?)])
    func locale(identifier: String, expected: String?) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Opened.schema]), now: { tracked })
        var context = ServiceContext.topLevel
        context[LocaleKey.self] = Locale(identifier: identifier)
        let record = EventRecord(event: Opened(), timestamp: tracked, sourceLocation: nil, context: context)

        let body = try #require(sut.requests(for: [record]).requests.first).body.body

        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let actual = (event["systemProps"] as? [String: Any])?["locale"] as? String
        #expect(actual == expected)
    }

    @Test("A system property at Aptabase's length is sent, and one character more is left out of the event, which is sent without it, counted in UTF-16", arguments: [
        ("osName", 30), ("osVersion", 100), ("appVersion", 50), ("appBuildNumber", 20), ("deviceModel", 100),
    ])
    func systemPropertyLength(property: String, maximum: Int) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Opened.schema]), now: { tracked })
        func record(_ value: String) -> EventRecord {
            var context = ServiceContext.topLevel
            switch property {
            case "osName": context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: value, version: "1")
            case "osVersion": context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "iOS", version: value)
            case "appVersion": context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: value, build: nil)
            case "appBuildNumber": context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: nil, build: value)
            default: context[DeviceKey.self] = DeviceKey.Value(model: value, formFactor: .phone)
            }
            return EventRecord(event: Opened(), timestamp: tracked, sourceLocation: nil, context: context)
        }
        let atLimit = String(repeating: "1", count: maximum)
        let emoji = String(repeating: "😀", count: maximum / 2)
        let batch = [atLimit, emoji, String(repeating: "1", count: maximum + 1), emoji + "1"].map(record)
        let expected: [String?] = [atLimit, emoji, nil, nil]

        let actual = sut.requests(for: batch)

        let body = try #require(actual.requests.first).body.body
        let events = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.requests.flatMap(\.recordIDs) == batch.map(\.id))
        #expect(events.map { ($0["systemProps"] as? [String: Any])?[property] as? String } == expected)
    }

    // A CFBundleVersion such as 2026.11.27.1432-abc1234 is over Aptabase's 20 characters, and the
    // standard context is the install's, so it is in every record the build tracks.
    @Test("Only the members too long are left out: the event keeps the rest of its system properties")
    func onlyLongMembersLeftOut() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Opened.schema]), now: { tracked })
        var context = ServiceContext.topLevel
        context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: String(repeating: "n", count: 31), version: "26.1.0")
        context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: "2.4.1", build: "2026.11.27.1432-abc1234")
        context[LocaleKey.self] = Locale(identifier: "en_US")
        let record = EventRecord(event: Opened(), timestamp: tracked, sourceLocation: nil, context: context)
        let expected = #""systemProps":{"appVersion":"2.4.1","isDebug":false,"locale":"en-US","osVersion":"26.1.0","sdkVersion":"Traffluent"}"#

        let actual = sut.requests(for: [record, record])

        let body = try #require(actual.requests.first).body.body
        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.requests.flatMap(\.recordIDs) == [record.id, record.id])
        #expect(String(decoding: body, as: UTF8.self).components(separatedBy: expected).count == 3)
    }
}
