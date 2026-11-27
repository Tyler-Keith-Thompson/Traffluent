// A server's build has both googleAnalytics factories: a declaration of each one's very name and
// parameters, returning another type, makes a call with nothing to choose between them ambiguous.
// The iOS half, where the same declarations compile as the only factories, is
// GoogleAnalyticsAvailabilityTests, which runs in the simulator.

import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import TrackingPlans

struct Absent {}

extension HTTPDestination where Encoding == GoogleAnalyticsBatchEncoder {
    static func googleAnalytics(
        measurementID: String,
        apiSecret: String,
        region: GoogleAnalyticsRegion,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) -> Absent {
        Absent()
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == GoogleAnalyticsBatchEncoder {
    static func googleAnalytics(
        measurementID: String,
        apiSecret: String,
        region: GoogleAnalyticsRegion,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date.now }
    ) -> Absent {
        Absent()
    }
}

func probe(plan: TrackingPlan) {
    _ = HTTPDestination.googleAnalytics(
        measurementID: "G-TEST000000",
        apiSecret: "testapisecret",
        region: .global,
        plan: plan,
        transport: URLSessionTransport(),
        backoff: ExponentialBackoff(),
        clock: ContinuousClock(),
        now: { Date.now }
    )
}

func probeURLSession(plan: TrackingPlan) {
    _ = HTTPDestination.googleAnalytics(
        measurementID: "G-TEST000000",
        apiSecret: "testapisecret",
        region: .global,
        plan: plan,
        backoff: ExponentialBackoff(),
        clock: ContinuousClock(),
        now: { Date.now }
    )
}
