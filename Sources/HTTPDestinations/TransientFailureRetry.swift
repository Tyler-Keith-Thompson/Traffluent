import Afluent
import HTTPTypes

/// Why one attempt at sending a batch didn't deliver it.
enum AttemptFailure: Error {
    /// No response arrived; retried.
    case unanswered(reason: String)
    /// The endpoint answered with a status a later attempt may not get (``HTTPResponse/Status/isTransient``);
    /// retried.
    case unavailable(HTTPResponse)
    /// The endpoint answered with a status every attempt would get; not retried.
    case rejected(HTTPResponse)
    /// The transport can never send the request; not retried.
    case invalidRequest(reason: String)
}

extension HTTPResponse.Status {
    /// Whether a request answered with this status may succeed when sent again: 408 Request
    /// Timeout, 429 Too Many Requests and every 5xx.
    var isTransient: Bool {
        kind == .serverError || self == .requestTimeout || self == .tooManyRequests
    }
}

/// Retries an ``AttemptFailure`` that may not happen again, after the wait an
/// ``ExponentialBackoff`` gives on `clock`, for as long as it keeps failing; any other error
/// isn't retried.
///
/// Afluent's `ExponentialBackoffStrategy` counts the retries and sleeps on the clock; this only
/// decides which errors reach it. One is made per batch, since the strategy keeps its count.
struct TransientFailureRetry<BackoffClock: Clock<Duration>>: RetryStrategy {
    private let backoff: RetryByBackoffStrategy<ExponentialBackoffStrategy<BackoffClock>>

    /// Retries with the waits of `backoff`, measured on `clock`.
    init(_ backoff: ExponentialBackoff, clock: BackoffClock) {
        self.backoff = RetryByBackoffStrategy(
            // A count below Int32.max, not Afluent's default of UInt.max: past Int.max it traps
            // converting the count on a 32-bit Int (AFLU-69, fixed after Afluent 1.1.46). Over
            // two billion retries of one batch is never in practice.
            ExponentialBackoffStrategy(base: 2, maxCount: UInt(Int32.max) - 1, maxDelay: backoff.maximumDelay),
            clock: clock,
            // Afluent's nth wait is the duration of 2ⁿ, counting n from 1, so the exponent is
            // the retry's number, one more than the doublings of the initial delay (AFLU-68: it
            // has no spelling for an initial delay). Once 2ⁿ
            // doesn't fit in Int, from retry 31 on a 32-bit Int (watchOS arm64_32) or 63 on a
            // 64-bit one, Afluent waits its maxDelay instead. So with maximumDelay more than 2³⁰
            // times initialDelay, a watch reaches the longest wait early: harmless, as the wait
            // only grows and never passes the maximum.
            durationUnit: { power in backoff.delay(afterDoubling: power.trailingZeroBitCount - 1) })
    }

    func handle(error: any Error, beforeRetry: @Sendable (any Error) async throws -> Void) async throws -> Bool {
        switch error as? AttemptFailure {
        case .unanswered, .unavailable:
            return try await backoff.handle(error: error, beforeRetry: beforeRetry)
        case .rejected, .invalidRequest, nil:
            return false
        }
    }
}
