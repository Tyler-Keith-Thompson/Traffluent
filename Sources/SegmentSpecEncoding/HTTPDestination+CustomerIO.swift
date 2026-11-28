import Foundation
public import HTTPDestinations
import HTTPTypes
import Instrumentation
public import TrackingPlans

extension HTTPDestination where Encoding == SegmentSpecBatchEncoder {
    /// A destination that sends batches to the Customer.io Data Pipelines source of `apiKey`, in a
    /// workspace in `region`, through `transport`, retrying a send that fails for now with the
    /// waits of `backoff` on `clock`.
    ///
    /// The destination posts to the Pipelines API's `/v1/batch` in `region`, encoded by a
    /// ``SegmentSpecBatchEncoder`` of `plan` within ``SegmentSpecBatchEncoder/batchLimit``, with
    /// the key as a bearer token and `X-Strict-Mode: 1`, and sends no trace context in its header
    /// fields. Without strict mode, Customer.io answers 200 for a request it drops, a key it
    /// doesn't know included; in it, Customer.io answers 401 for a missing or wrong key and 400
    /// for a request it won't process, and the destination drops and reports both. It retries no
    /// response, a 5xx, 408 or 429. In strict mode Customer.io refuses a whole batch when one call
    /// in it fails, so the encoder leaves out each call Customer.io documents refusing; a 400 for
    /// anything else drops the whole request.
    ///
    /// Each call carries `context.ip` as `"0.0.0.0"`. Customer.io's references don't say whether
    /// it takes that in place of the address it reads from an HTTP request.
    ///
    /// Customer.io's public keys (`pk_...`) are client keys, safe to ship in an app: they let a
    /// client send data to the source and read nothing. Its private keys (`sk_...`) reach every
    /// Customer.io API, deleting people included, and must not ship in an app, so the factory
    /// refuses one.
    ///
    /// - Parameters:
    ///   - apiKey: The source's public key (`pk_...`), from the workspace's API Credentials page,
    ///     or a legacy Pipelines write key. Whitespace and newlines around it are trimmed off.
    ///   - region: Where the workspace is: ``CustomerIORegion/us`` or ``CustomerIORegion/eu``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - transport: What sends each request.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``CustomerIOSetupError/emptyAPIKey`` for a key that is empty or only whitespace,
    ///   ``CustomerIOSetupError/privateKey`` for a private key (`sk_...`), and
    ///   ``CustomerIOSetupError/regionMismatch`` for a key whose region (`pk_us_...`,
    ///   `pk_eu_...`) isn't `region`.
    public static func customerIO(
        apiKey: String,
        region: CustomerIORegion,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(CustomerIOSetupError) -> HTTPDestination<Transport, SegmentSpecBatchEncoder> {
        // Trimmed once, so a key pasted with a newline is checked and sent without it.
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw .emptyAPIKey
        }
        // Customer.io's keys start with their kind and region, `pk_us_` or `sk_eu_` (Managing
        // credentials, https://docs.customer.io/accounts/settings/managing-credentials/). A legacy
        // write key has neither, so it is checked for nothing more. Case-sensitive, as Customer.io
        // issues them in lowercase.
        guard !apiKey.hasPrefix("sk_") else {
            throw .privateKey
        }
        if let keyRegion = CustomerIORegion(publicKey: apiKey), keyRegion != region {
            throw .regionMismatch
        }
        // Customer.io doesn't read a trace context, so the app's traces aren't sent to it.
        let instrument: any Instrument = NoOpInstrument()
        var headerFields: HTTPFields = [.authorization: "Bearer \(apiKey)"]
        // Strict mode turns Customer.io's silent drops (a wrong key, a malformed call) into
        // statuses the destination reports. Its cost, a whole batch refused for one bad call, the
        // encoder keeps down by leaving out each call Customer.io documents refusing; a 400 for
        // anything else drops the whole request, which the destination reports.
        if let strictMode = HTTPField.Name("X-Strict-Mode") {
            headerFields[strictMode] = "1"
        }
        return HTTPDestination(
            endpoint: region.endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: transport,
            encoder: SegmentSpecBatchEncoder(plan: plan),
            backoff: backoff,
            clock: clock)
    }
}

extension HTTPDestination where Transport == URLSessionTransport, Encoding == SegmentSpecBatchEncoder {
    /// A destination that sends batches to the Customer.io Data Pipelines source of `apiKey`, in a
    /// workspace in `region`, with `URLSession.shared`, retrying a send that fails for now with the
    /// waits of `backoff` on `clock`.
    ///
    /// ```swift
    /// let customerIO = try HTTPDestination.customerIO(
    ///     apiKey: apiKey,  // the source's public key, pk_…
    ///     region: .us,  // or .eu, where the workspace is
    ///     plan: plan)
    /// ```
    ///
    /// It is ``HTTPDestinations/HTTPDestination/customerIO(apiKey:region:plan:transport:backoff:clock:)``
    /// with a `URLSessionTransport`.
    ///
    /// - Parameters:
    ///   - apiKey: The source's public key (`pk_...`), or a legacy Pipelines write key; never a
    ///     private key (`sk_...`). Whitespace and newlines around it are trimmed off.
    ///   - region: Where the workspace is: ``CustomerIORegion/us`` or ``CustomerIORegion/eu``.
    ///   - plan: The tracking plan of every event the destination is given.
    ///   - backoff: How long to wait before each new attempt at a request; 1 second, doubling up
    ///     to 60 seconds, with full jitter, by default.
    ///   - clock: The clock the waits are measured on.
    /// - Returns: The destination.
    /// - Throws: ``CustomerIOSetupError`` for an empty key, a private key, or a key of the other
    ///   region, as the other spelling says.
    public static func customerIO(
        apiKey: String,
        region: CustomerIORegion,
        plan: TrackingPlan,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock()
    ) throws(CustomerIOSetupError) -> HTTPDestination<URLSessionTransport, SegmentSpecBatchEncoder> {
        try customerIO(apiKey: apiKey, region: region, plan: plan, transport: URLSessionTransport(), backoff: backoff, clock: clock)
    }
}

extension CustomerIORegion {
    /// The region a public key names after its kind (`pk_us_...`, `pk_eu_...`), or `nil` for a
    /// key that names none, such as a legacy write key.
    fileprivate init?(publicKey: String) {
        if publicKey.hasPrefix("pk_us_") {
            self = .us
        } else if publicKey.hasPrefix("pk_eu_") {
            self = .eu
        } else {
            return nil
        }
    }

    /// The region's Pipelines API batch endpoint (https://docs.customer.io/api/cdp/, "Server
    /// addresses").
    fileprivate var endpoint: URL {
        // Foundation has no non-failable initializer for a literal URL. These literals always
        // parse, so the fallback is never taken, and the endpoint test pins both. The URL macro
        // would check them at compile time, but it would add a macro package to every adopter's
        // build for two literals.
        switch self {
        case .us: URL(string: "https://cdp.customer.io/v1/batch") ?? URL(fileURLWithPath: "/")
        case .eu: URL(string: "https://cdp-eu.customer.io/v1/batch") ?? URL(fileURLWithPath: "/")
        }
    }
}
