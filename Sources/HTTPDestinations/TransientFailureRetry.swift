import Afluent
import Foundation
import HTTPTypes

/// Why one attempt at sending a batch didn't deliver it.
enum AttemptFailure: Error {
    /// No response arrived; retried.
    case unanswered(reason: String)
    /// The endpoint answered with a status a later attempt may not get
    /// (``HTTPResponse/Status/isTransient``, or one of the encoder's
    /// ``BatchEncoder/transientStatuses``), or with a 2xx whose body its encoder reads as storing
    /// nothing for now (``ResponseOutcome/transient(reason:)``); retried.
    case unavailable(HTTPResponse)
    /// The endpoint answered with a status every attempt would get; not retried.
    case rejected(HTTPResponse)
    /// The endpoint answered 2xx, with a body its encoder reads as storing nothing, for a reason
    /// every attempt would meet (``ResponseOutcome/rejected(reason:)``); not retried.
    case rejectedInBody(HTTPResponse, reason: String)
    /// The transport can never send the request; not retried.
    case invalidRequest(reason: String)
    /// The request's deadline passed before this attempt; not retried.
    case deadlineExceeded(Date)
}

extension HTTPResponse.Status {
    /// Whether a request answered with this status may succeed when sent again, from any
    /// endpoint: 408 Request Timeout, 429 Too Many Requests and every 5xx. An encoder adds its
    /// vendor's own (``BatchEncoder/transientStatuses``).
    var isTransient: Bool {
        kind == .serverError || self == .requestTimeout || self == .tooManyRequests
    }
}

/// Retries an ``AttemptFailure`` that may not happen again, after the wait an
/// ``ExponentialBackoff`` gives on `clock`, for as long as it keeps failing; any other error
/// isn't retried.
///
/// Afluent's `ExponentialBackoffStrategy` doubles the waits up to the maximum, jitters them and
/// sleeps them on the clock; this only decides which errors reach it. One is made per request
/// (``HTTPDestination``'s `retryStrategy`, called in `send`), since the strategy keeps its next
/// wait, and so is its Afluent jitter, which keeps nothing of its own here: every request's jitter
/// draws from the destination's one shared generator.
struct TransientFailureRetry<BackoffClock: Clock<Duration>>: RetryStrategy {
    private let backoff: RetryByBackoffStrategy<ExponentialBackoffStrategy<BackoffClock>>

    /// Retries with the waits of `backoff`, measured on `clock`, its jitter drawn from
    /// `generator`.
    init(_ backoff: ExponentialBackoff, clock: BackoffClock, generator: SharedRandomNumberGenerator) {
        // Afluent's initializer traps on a negative initial delay, or a multiplier below 1 or that
        // isn't finite. None can happen: ExponentialBackoff refuses an initial delay that isn't
        // positive, and the multiplier is the literal 2. Its default maxCount retries for ever, the
        // count saturating rather than overflowing, on a 32-bit Int too.
        //
        // Afluent doubles each wait as a `Duration * Double`, and compares it with the maximum as
        // a `Duration / Duration` quotient, so the nominal waits are ExponentialBackoff's exactly
        // while both delays count their attoseconds in 53 significant bits or fewer (any whole
        // number of milliseconds under 295 s does), and within about one part in 2⁵³ of them
        // otherwise.
        self.backoff = RetryByBackoffStrategy(
            ExponentialBackoffStrategy(initialDelay: backoff.initialDelay, multiplier: 2, maxDelay: backoff.maximumDelay, jitter: backoff.jitter.afluentJitter(using: generator)),
            clock: clock)
    }

    func handle(error: any Error, beforeRetry: @Sendable (any Error) async throws -> Void) async throws -> Bool {
        switch error as? AttemptFailure {
        case .unanswered, .unavailable:
            return try await backoff.handle(error: error, beforeRetry: beforeRetry)
        case .rejected, .rejectedInBody, .invalidRequest, .deadlineExceeded, nil:
            return false
        }
    }
}

extension ExponentialBackoff.Jitter {
    /// Afluent's jitter of this kind, drawing from `generator`.
    ///
    /// Afluent's kinds follow "Exponential Backoff And Jitter" (AWS Architecture Blog,
    /// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/). Its full jitter
    /// is the article's `sleep = random_between(0, min(cap, base * 2 ** attempt))`: one draw a
    /// wait, whose top 32 bits pick a point of the wait by halving its attoseconds, integer
    /// arithmetic that gives a seed the same waits on every platform. Afluent's decorrelated jitter
    /// isn't offered: its waits start from the nominal wait, where the article's
    /// `random_between(base, sleep * 3)` starts from the base, and each depends on the wait before,
    /// which `delay(beforeRetry:)` can't state. Nor is equal jitter, which the article finds does
    /// more work than full jitter for no less contention.
    fileprivate func afluentJitter(using generator: SharedRandomNumberGenerator) -> BackoffJitter {
        switch self {
        case .none: BackoffJitter.none
        case .full: BackoffJitter.full(using: generator)
        }
    }
}
