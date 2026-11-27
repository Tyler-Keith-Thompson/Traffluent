import AptabaseEncoding
import DestinationTesting
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import Testing
import TrackingPlans

// Aptabase's server makes a key as $"A-{Region}-{NanoId.Numbers(10)}", its region EU or US in its
// cloud, SH when self-hosted and DEV in development (github.com/aptabase/aptabase at 89d36185,
// src/Features/Apps/AppsController.cs and src/Features/EnvSettings.cs, read 2026-11-27); its Swift
// SDK takes a key of three parts whose region is US, EU, DEV or SH, and needs a host for SH
// (github.com/aptabase/aptabase-swift at a1ee53e9, Aptabase.swift).
@Suite("HTTPDestination.aptabase: setup errors", .timeLimit(.minutes(1)))
struct AptabaseSetupErrorTests {
    @Test("The factory throws emptyAppKey for an app key that is empty or only whitespace", arguments: [
        "", " ", "\n", " \t\r\n ",
    ])
    func emptyAppKey(appKey: String) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected = AptabaseSetupError.emptyAppKey

        #expect(throws: expected) {
            try HTTPDestination.aptabase(appKey: appKey, isDebug: false, plan: plan)
        }
    }

    // The body's range is checked at each end and just past it: '/' and ':' are around '0'...'9',
    // '@' and '[' around 'A'...'Z', and '`' and '{' around 'a'...'z' in ASCII.
    @Test("The factory throws malformedAppKey for a key that isn't A-<region>-<letters and digits>, and takes one that is", arguments: [
        ("A-EU-", true), ("A-EU", true), ("A-", true), ("A", true), ("EU-1234567890", true), ("1234567890", true),
        ("B-EU-1234567890", true), ("a-EU-1234567890", true), ("AA-EU-1234567890", true), ("-EU-1234567890", true),
        ("A-EU-1234567890-1", true), ("A-EU-12 34", true), ("A-EU-1/", true), ("A-EU-1:", true), ("A-EU-1@", true),
        ("A-EU-1[", true), ("A-EU-1`", true), ("A-EU-1{", true), ("A-EU-١٢", true), ("A-EU-é", true), ("A_EU_1234567890", true),
        ("A-EU-0", false), ("A-EU-9", false), ("A-EU-A", false), ("A-EU-Z", false), ("A-EU-a", false), ("A-EU-z", false),
        ("A-EU-1234567890", false), ("A-US-0000000000", false), ("A-EU-1", false), (" A-EU-1234567890\n", false),
    ])
    func malformedAppKey(appKey: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected: AptabaseSetupError? = throwsError ? .malformedAppKey : nil

        let actual: AptabaseSetupError?
        do {
            _ = try HTTPDestination.aptabase(appKey: appKey, isDebug: false, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The factory throws unknownRegion for a region other than EU, US, SH and DEV, written in capitals", arguments: [
        "A-eu-1234567890", "A-Eu-1234567890", "A-us-1234567890", "A-sh-1234567890", "A-dev-1234567890",
        "A-UK-1234567890", "A-E-1234567890", "A-EUR-1234567890", "A-USA-1234567890", "A--1234567890", "A-SHH-1234567890", "A-DE-1234567890",
    ])
    func unknownRegion(appKey: String) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected = AptabaseSetupError.unknownRegion

        #expect(throws: expected) {
            try HTTPDestination.aptabase(appKey: appKey, isDebug: false, plan: plan)
        }
    }

    @Test("A self-hosted or development key without a host throws selfHostedAppKeyWithoutHost", arguments: ["A-SH-1234567890", "A-DEV-1234567890"])
    func selfHostedWithoutHost(appKey: String) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected = AptabaseSetupError.selfHostedAppKeyWithoutHost

        #expect(throws: expected) {
            try HTTPDestination.aptabase(appKey: appKey, isDebug: false, plan: plan)
        }
    }

    @Test("A cloud key with a host throws cloudAppKeyWithHost, even a host of Aptabase's own", arguments: [
        ("A-EU-1234567890", "https://aptabase.example.com"),
        ("A-US-1234567890", "https://aptabase.example.com"),
        ("A-EU-1234567890", "https://eu.aptabase.com"),
        ("A-US-1234567890", "https://us.aptabase.com"),
    ])
    func cloudWithHost(appKey: String, host: String) throws {
        let plan = try TrackingPlan(schemas: [])
        let url = try #require(URL(string: host))
        let expected = AptabaseSetupError.cloudAppKeyWithHost

        #expect(throws: expected) {
            try HTTPDestination.aptabase(appKey: appKey, host: url, isDebug: false, plan: plan)
        }
    }

    @Test("A host that isn't a plain https URL of the server throws invalidHost", arguments: [
        "http://aptabase.example.com", "ftp://aptabase.example.com", "aptabase.example.com", "/api",
        "https://user@aptabase.example.com", "https://user:secret@aptabase.example.com", "https://:secret@aptabase.example.com",
        "https://aptabase.example.com?key=1", "https://aptabase.example.com#top", "https://aptabase.example.com/?",
        "https://aptabase.example.com/api/v0/events", "https://aptabase.example.com/api/v0/event", "https://aptabase.example.com/API/V0/Events/",
        "https://aptabase.example.com/x/api/v0/events//", "https:///aptabase",
    ])
    func invalidHost(host: String) throws {
        let plan = try TrackingPlan(schemas: [])
        let url = try #require(URL(string: host))
        let expected = AptabaseSetupError.invalidHost

        #expect(throws: expected) {
            try HTTPDestination.aptabase(appKey: "A-SH-1234567890", host: url, isDebug: false, plan: plan)
        }
    }

    @Test("A host whose path only resembles the endpoint is taken", arguments: [
        "https://aptabase.example.com/api/v0", "https://aptabase.example.com/api/v0/eventsx", "https://aptabase.example.com/api/v1/events",
        "https://aptabase.example.com/api/v0/events/x", "HTTPS://aptabase.example.com",
    ])
    func validHost(host: String) throws {
        let plan = try TrackingPlan(schemas: [])
        let url = try #require(URL(string: host))

        #expect(throws: Never.self) {
            try HTTPDestination.aptabase(appKey: "A-SH-1234567890", host: url, isDebug: false, plan: plan)
        }
    }

    @Test("The App-Key header field holds the key trimmed of whitespace and newlines, as given otherwise")
    func trimmedAppKey() async throws {
        struct Opened: Event, Codable {
            static let name = "opened"
        }
        let schema = EventSchema(name: "opened", version: 1, consentCategory: .analytics, properties: [])
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.aptabase(appKey: " \tA-EU-1234567890\n", isDebug: false, plan: try TrackingPlan(schemas: [schema]), transport: transport, now: { tracked })
        let record = EventRecord(event: Opened(), timestamp: tracked, sourceLocation: nil)
        let appKeyField = try #require(HTTPField.Name("App-Key"))
        let expected = "A-EU-1234567890"

        await sut.receive([record])

        let actual = try #require(transport.requests.first).request.headerFields[appKeyField]
        #expect(actual == expected)
    }

    @Test("A plan holding an event or property Aptabase refuses still sets up: only its records are skipped")
    func planWithRefusedNames() throws {
        let longName = EventSchema(name: String(repeating: "e", count: 61), version: 1, consentCategory: .analytics, properties: [])
        let blankName = EventSchema(name: " ", version: 1, consentCategory: .analytics, properties: [])
        let longProperty = EventSchema(name: "searched", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: String(repeating: "p", count: 41), typeName: "String", isOptional: false)])
        let plan = try TrackingPlan(schemas: [longName, blankName, longProperty])

        #expect(throws: Never.self) {
            try HTTPDestination.aptabase(appKey: "A-US-1234567890", isDebug: true, plan: plan)
        }
    }
}
