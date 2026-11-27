import Afluent
import Foundation
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
    /// The request's deadline passed before this attempt; not retried.
    case deadlineExceeded(Date)
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
/// Afluent's `ExponentialBackoffStrategy` doubles the waits up to the maximum and sleeps them on
/// the clock; this only decides which errors reach it. One is made per batch, since the strategy
/// keeps its next wait.
struct TransientFailureRetry<BackoffClock: Clock<Duration>>: RetryStrategy {
    private let backoff: RetryByBackoffStrategy<ExponentialBackoffStrategy<BackoffClock>>

    /// Retries with the waits of `backoff`, measured on `clock`.
    init(_ backoff: ExponentialBackoff, clock: BackoffClock) {
        // Afluent's initializer traps on a negative initial delay, or a multiplier below 1 or that
        // isn't finite. None can happen: ExponentialBackoff refuses an initial delay that isn't
        // positive, and the multiplier is the literal 2. Its default maxCount retries for ever, the
        // count saturating rather than overflowing, on a 32-bit Int too.
        //
        // Afluent doubles each wait as a `Duration * Double`, and compares it with the maximum as
        // a `Duration / Duration` quotient, so the waits are ExponentialBackoff's exactly while
        // both delays count their attoseconds in 53 significant bits or fewer (any whole number of
        // milliseconds under 295 s does), and within about one part in 2⁵³ of them otherwise.
        self.backoff = RetryByBackoffStrategy(
            ExponentialBackoffStrategy(initialDelay: backoff.initialDelay, multiplier: 2, maxDelay: backoff.maximumDelay),
            clock: clock)
    }

    func handle(error: any Error, beforeRetry: @Sendable (any Error) async throws -> Void) async throws -> Bool {
        switch error as? AttemptFailure {
        case .unanswered, .unavailable:
            return try await backoff.handle(error: error, beforeRetry: beforeRetry)
        case .rejected, .invalidRequest, .deadlineExceeded, nil:
            return false
        }
    }
}
