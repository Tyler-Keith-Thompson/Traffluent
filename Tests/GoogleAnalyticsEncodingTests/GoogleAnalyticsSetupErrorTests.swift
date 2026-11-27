// The factory is compiled for macOS and Linux alone (HTTPDestination+GoogleAnalytics.swift).
#if os(macOS) || os(Linux)
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import Testing
import TrackingPlans

@Suite("HTTPDestination.googleAnalytics: setup errors")
struct GoogleAnalyticsSetupErrorTests {
    @Test("The factory throws emptyMeasurementID for a measurement ID that is empty or only whitespace", arguments: ["", " ", " \n\t"])
    func emptyMeasurementID(measurementID: String) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: GoogleAnalyticsSetupError.emptyMeasurementID) {
            try HTTPDestination.googleAnalytics(measurementID: measurementID, apiSecret: "secret", region: .global, plan: plan)
        }
    }

    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events: a
    // web stream's measurement ID "usually starts with G-" (read on 2026-11-27).
    @Test("The factory throws malformedMeasurementID for a measurement ID that isn't G- and at least one uppercase ASCII letter or digit, and accepts every one that is", arguments: [
        ("G-TEST000000", false), ("G-A", false), ("G-0", false), ("G-Z9", false), ("G-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", false), (" G-ABC123\n", false),
        ("G-", true), ("G", true), ("g-ABC123", true), ("G-abc123", true), ("G-ABC 123", true), ("G-ABC-123", true), ("G_ABC123", true), ("UA-12345-1", true),
        ("AW-123456", true), ("1:1234567890:android:abc", true), ("G-ABC123?x=1", true), ("G-ABCÉ", true), ("G-AB٣", true), ("XG-ABC123", true), ("G-@", true),
        ("G-[", true), ("G-/", true), ("G-:", true),
    ])
    func malformedMeasurementID(measurementID: String, throwsError: Bool) throws {
        let plan = try TrackingPlan(schemas: [])
        let expected: GoogleAnalyticsSetupError? = throwsError ? .malformedMeasurementID : nil

        let actual: GoogleAnalyticsSetupError?
        do {
            _ = try HTTPDestination.googleAnalytics(measurementID: measurementID, apiSecret: "secret", region: .global, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The factory throws emptyAPISecret for a secret that is empty or only whitespace", arguments: ["", " ", " \n\t"])
    func emptyAPISecret(apiSecret: String) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: GoogleAnalyticsSetupError.emptyAPISecret) {
            try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: apiSecret, region: .global, plan: plan)
        }
    }

    @Test("The factory accepts a one-character secret, the shortest that isn't empty, in every region", arguments: [GoogleAnalyticsRegion.global, .eu])
    func shortestSecret(region: GoogleAnalyticsRegion) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: Never.self) {
            try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "a", region: region, plan: plan)
        }
    }

    // An app's main bundle is a directory named .app, an app extension's .appex; a server's, a
    // command-line tool's and a test runner's is the directory of its executable, or a bundle of
    // another kind.
    @Test("The bundle check throws appBundle for an app's or an app extension's bundle, in any case, and passes any other", arguments: [
        ("/Applications/Shop.app", true), ("/Applications/Shop.app/", true), ("/Users/ada/Shop.APP", true), ("/Applications/Shop.app/Contents/PlugIns/Share.appex", true),
        ("/usr/local/bin", false), ("/srv/relay/.build/release", false), ("/Applications/Xcode.app/Contents/Developer/usr/bin", false),
        ("/tmp/Tests.xctest", false), ("/Library/Bundles/Helper.bundle", false), ("/Library/Frameworks/Kit.framework", false), ("/srv/apps", false), ("/srv/app", false),
        ("/opt/Shop.application", false), ("/", false),
    ] as [(String, Bool)])
    func applicationBundle(path: String, refused: Bool) {
        let bundleURL = URL(fileURLWithPath: path, isDirectory: true)
        let expected: GoogleAnalyticsSetupError? = refused ? .appBundle : nil

        let actual: GoogleAnalyticsSetupError?
        do {
            try refuseApplicationBundle(bundleURL)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The factory makes a destination in this test runner, whose main bundle isn't an app's")
    func testRunnerAccepted() throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: Never.self) {
            try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "secret", region: .global, plan: plan)
        }
    }

    @Test("The measurement ID is checked before the secret: an empty ID with an empty secret throws emptyMeasurementID, and a malformed one malformedMeasurementID", arguments: [
        ("", GoogleAnalyticsSetupError.emptyMeasurementID), ("UA-1", .malformedMeasurementID), ("G-TEST000000", .emptyAPISecret),
    ])
    func checkOrder(measurementID: String, expected: GoogleAnalyticsSetupError) throws {
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: expected) {
            try HTTPDestination.googleAnalytics(measurementID: measurementID, apiSecret: "", region: .global, plan: plan)
        }
    }
}
#endif
