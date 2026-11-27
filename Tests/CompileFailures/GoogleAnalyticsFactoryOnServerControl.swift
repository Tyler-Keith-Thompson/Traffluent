// The same call with the probe's declaration taken out compiles, so the check beside it fails for
// the ambiguity alone and not because this rule can't build the fixture: on a server, the library's
// factories are the ones it finds.

import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import TrackingPlans

func probe(plan: TrackingPlan) throws {
    _ = try HTTPDestination.googleAnalytics(
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

func probeURLSession(plan: TrackingPlan) throws {
    _ = try HTTPDestination.googleAnalytics(
        measurementID: "G-TEST000000",
        apiSecret: "testapisecret",
        region: .global,
        plan: plan,
        backoff: ExponentialBackoff(),
        clock: ContinuousClock(),
        now: { Date.now }
    )
}
