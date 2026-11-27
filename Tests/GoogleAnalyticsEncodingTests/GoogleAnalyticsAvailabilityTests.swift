// GoogleAnalyticsEncoding is compiled for macOS and Linux alone. On iOS this file names each of its
// public types, which TraffluentTestSupport declares on iOS too: were the module's there, each name
// would be ambiguous and this target would fail to compile in the simulator. It also declares a
// factory of each spelling's very name and parameters, returning another type, and calls them with
// nothing to choose between: were the module's factories there, the calls would be ambiguous.
// Tests/CompileFailures pins the reverse on the host, where both factories must be found.
#if !(os(macOS) || os(Linux))
import Clocks
import Events
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("GoogleAnalyticsEncoding: availability")
struct GoogleAnalyticsAvailabilityTests {
    struct Absent: Equatable {}

    struct Failure: Error {}

    /// An encoder of the probe's own, as GoogleAnalyticsBatchEncoder isn't one on iOS.
    struct ProbeEncoder: BatchEncoder {
        static let transientStatuses: Set<TransientStatus> = []

        typealias Failure = GoogleAnalyticsAvailabilityTests.Failure

        func requests(for batch: [EventRecord]) throws(Failure) -> BatchRequests<Failure> {
            BatchRequests(requests: [], skippedRecords: [])
        }
    }

    @Test("An iOS build has none of the module's types: each name is TraffluentTestSupport's stand-in alone")
    func noTypesOnIOS() {
        let expected = 4

        let actual: [Any.Type] = [GoogleAnalyticsRegion.self, GoogleAnalyticsBatchEncoder.self, GoogleAnalyticsSetupError.self, GoogleAnalyticsEncodingError.self]

        #expect(actual.count == expected)
    }

    @Test("An iOS build has no googleAnalytics factory taking a transport: a declaration of its very name and parameters is the only one a call finds")
    func noFactoryOnIOS() throws {
        let plan = try TrackingPlan(schemas: [])
        let expected = Absent()

        let actual = HTTPDestination.googleAnalytics(
            measurementID: "G-TEST000000",
            apiSecret: "testapisecret",
            region: .global,
            plan: plan,
            transport: URLSessionTransport(),
            backoff: ExponentialBackoff(),
            clock: ContinuousClock(),
            now: { Date.now }
        )

        #expect(actual == expected)
    }

    @Test("An iOS build has no googleAnalytics factory with URLSession: a declaration of its very name and parameters is the only one a call finds")
    func noURLSessionFactoryOnIOS() throws {
        let plan = try TrackingPlan(schemas: [])
        let expected = Absent()

        let actual = HTTPDestination.googleAnalytics(
            measurementID: "G-TEST000000",
            apiSecret: "testapisecret",
            region: .global,
            plan: plan,
            backoff: ExponentialBackoff(),
            clock: ContinuousClock(),
            now: { Date.now }
        )

        #expect(actual == expected)
    }
}

extension HTTPDestination where Encoding == GoogleAnalyticsAvailabilityTests.ProbeEncoder {
    static func googleAnalytics(
        measurementID: String,
        apiSecret: String,
        region: GoogleAnalyticsRegion,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) -> GoogleAnalyticsAvailabilityTests.Absent {
        GoogleAnalyticsAvailabilityTests.Absent()
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == GoogleAnalyticsAvailabilityTests.ProbeEncoder {
    static func googleAnalytics(
        measurementID: String,
        apiSecret: String,
        region: GoogleAnalyticsRegion,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) -> GoogleAnalyticsAvailabilityTests.Absent {
        GoogleAnalyticsAvailabilityTests.Absent()
    }
}
#endif
