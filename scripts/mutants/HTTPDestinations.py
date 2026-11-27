# Planted bugs for HTTPDestinations; run with `just mutate HTTPDestinations`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/HTTPDestinations/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Dropping or changing a `logger.error` in `receive(_:)` or a `logger.notice` in `Attempt.run()`:
#   logs are for developers, and tests don't pin them (AGENTS.md). What each outcome is, which
#   decides what is logged, is pinned through `send(_:)` and `dropReports`.
# - `delay < maximumDelay - delay` as `<=` in ExponentialBackoff.delay(beforeRetry:): when they
#   are equal, doubling gives exactly the maximum, which is what the guard returns.
# - Loosening or removing `precondition(retry >= 1, ...)` in delay(beforeRetry:): a retry below 1
#   makes `1 ..< retry` an invalid range, which traps too; the precondition only names the cause.
# - Leaving out `|| error is CancellationError` in URLSessionTransport: a CancellationError comes
#   only from a cancelled task, which `Task.isCancelled` already catches.
# - Anything in URLSession+UploadWithoutCancelling.swift: it compiles only with FoundationNetworking
#   (Linux), and mutation runs on the Mac, where the file is empty. URLSessionTransportTests pin it
#   under `swift test` on Linux, cancelRacingRefusal among them.
#
# Not pinned: URLSessionTransport's `.badURL` and `.appTransportSecurityRequiresSecureConnection`
# as invalid requests (no URL reliably produces either on both macOS and Linux in a test; the
# `.unsupportedURL` case beside them is pinned with a `foo://` URL). And the URLSession
# convenience init passing `backoff:` on (urlsessionbackoffignored would survive). Its sends go to a real URLSession, and with no server to count requests, a test
# can't tell one wait from another; the designated init's tests pin what a backoff does.
#
# `injectedaftercontenttype` comes before the other mutants of those lines, which would otherwise
# wrap them apart; its schema then holds their text twice, so they pick the original with `nth=1`.

TESTS = ["HTTPDestinationsTests"]

D = "HTTPDestination.swift"
U = "URLSessionTransport.swift"
I = "HTTPFieldsInjector.swift"
S = "HTTPDestination+URLSessionTransport.swift"
E = "ExponentialBackoff.swift"
R = "TransientFailureRetry.swift"

# TransientFailureRetry's maxCount below Int32.max (AFLU-69) has no mutant: only a 2^31st retry
# would tell it from Afluent's default.
MUTANTS = [
    Mutant("methodput", D, "request = HTTPRequest(method: .post, url: endpoint, headerFields: headerFields)", "request = HTTPRequest(method: .put, url: endpoint, headerFields: headerFields)", mode="stmt"),
    Mutant("noheaderfields", D, "request = HTTPRequest(method: .post, url: endpoint, headerFields: headerFields)", "request = HTTPRequest(method: .post, url: endpoint)", mode="stmt"),
    Mutant("lastrecordonly", D, "encoded = try encoder.encode(batch)", "encoded = try encoder.encode(Array(batch.suffix(1)))", mode="stmt"),
    Mutant("injectedaftercontenttype", D, """if let first = batch.first {
            instrument.inject(first.context, into: &request.headerFields, using: HTTPFieldsInjector())
        }
        request.headerFields[.contentType] = encoded.contentType""", """request.headerFields[.contentType] = encoded.contentType
        if let first = batch.first {
            instrument.inject(first.context, into: &request.headerFields, using: HTTPFieldsInjector())
        }""", mode="stmt"),
    Mutant("nocontenttype", D, "request.headerFields[.contentType] = encoded.contentType", "", mode="stmt", nth=1),
    Mutant("configuredcontenttypewins", D, "request.headerFields[.contentType] = encoded.contentType", "request.headerFields[.contentType] = request.headerFields[.contentType] ?? encoded.contentType", mode="stmt", nth=1),
    Mutant("emptybody", D, "encoded.body", "Data()"),
    Mutant("noinjection", D, "instrument.inject(first.context, into: &request.headerFields, using: HTTPFieldsInjector())", "", mode="stmt", nth=1),
    Mutant("lastrecordcontext", D, "first.context", "batch[batch.count - 1].context", nth=1),
    Mutant("firstrecordindexed", D, "batch.first", "Optional(batch[0])", nth=1),
    Mutant("instrumentignored", D, "self.instrument = instrument", "self.instrument = InstrumentationSystem.instrument", mode="stmt"),
    # Outcomes and reports.
    Mutant("noretry", D, """let response = try await DeferredTask { try await attempt.run() }
                .retry(retryStrategy())
                .execute()
            return .delivered(response)""", """let response = try await DeferredTask { try await attempt.run() }
                .execute()
            return .delivered(response)""", mode="stmt"),
    Mutant("encodingerrorlost", D, "return .notEncoded(error)", "return .cancelled", mode="stmt"),
    Mutant("deliveredascancelled", D, "return .delivered(response)", "return .cancelled", mode="stmt", nth=1),
    Mutant("rejectedascancelled", D, "return .rejected(response)", "return .cancelled", mode="stmt"),
    Mutant("rejectionnotreported", D, "reporter.report(.rejected(status: response.status, recordIDs: batch.map(\\.id)))", "", mode="stmt"),
    Mutant("rejectionstatuslost", D, "reporter.report(.rejected(status: response.status, recordIDs: batch.map(\\.id)))", "reporter.report(.rejected(status: .badRequest, recordIDs: batch.map(\\.id)))", mode="stmt"),
    Mutant("rejectionidslost", D, "reporter.report(.rejected(status: response.status, recordIDs: batch.map(\\.id)))", "reporter.report(.rejected(status: response.status, recordIDs: Array(batch.map(\\.id).prefix(1))))", mode="stmt"),
    Mutant("invalidrequestascancelled", D, "return .invalidRequest(reason)", "return .cancelled", mode="stmt"),
    Mutant("invalidrequestnotreported", D, "reporter.report(.invalidRequest(reason: reason, recordIDs: batch.map(\\.id)))", "", mode="stmt"),
    Mutant("invalidrequestreasonlost", D, "reporter.report(.invalidRequest(reason: reason, recordIDs: batch.map(\\.id)))", "reporter.report(.invalidRequest(reason: \"\", recordIDs: batch.map(\\.id)))", mode="stmt"),
    Mutant("invalidrequestidslost", D, "reporter.report(.invalidRequest(reason: reason, recordIDs: batch.map(\\.id)))", "reporter.report(.invalidRequest(reason: reason, recordIDs: []))", mode="stmt"),
    # The four mutants before this one that return `.cancelled` sit above it in the file, so the
    # original `return .cancelled` (under `catch is CancellationError`) is the fifth.
    Mutant("cancellationabandoned", D, "return .cancelled", "return .abandoned(CancellationError())", mode="stmt", nth=4),
    Mutant("abandonedascancelled", D, "return .abandoned(error)", "return .cancelled", mode="stmt"),
    Mutant("encodingnotreported", D, "reporter.report(.notEncoded(error, recordIDs: batch.map(\\.id)))", "", mode="stmt"),
    Mutant("encodingidslost", D, "reporter.report(.notEncoded(error, recordIDs: batch.map(\\.id)))", "reporter.report(.notEncoded(error, recordIDs: []))", mode="stmt"),
    Mutant("reportsneverend", D, "reports.finish()", "", mode="stmt"),
    # Attempts and retries.
    Mutant("backoffignored", D, "retryStrategy = { TransientFailureRetry(backoff, clock: clock) }", "retryStrategy = { TransientFailureRetry(ExponentialBackoff(), clock: clock) }", mode="stmt"),
    Mutant("clockignored", D, "retryStrategy = { TransientFailureRetry(backoff, clock: clock) }", "retryStrategy = { TransientFailureRetry(backoff, clock: ContinuousClock()) }", mode="stmt"),
    Mutant("strategysharedacrossbatches", D, "retryStrategy = { TransientFailureRetry(backoff, clock: clock) }", "let strategy = TransientFailureRetry(backoff, clock: clock)\n        retryStrategy = { strategy }", mode="stmt"),
    Mutant("everystatusdelivered", D, "status.kind == .successful", "true"),
    Mutant("nostatusdelivered", D, "status.kind == .successful", "false"),
    Mutant("below300delivered", D, "status.kind == .successful", "status.code < 300"),
    Mutant("only200delivered", D, "status.kind == .successful", "status.code == 200"),
    Mutant("unansweredrejected", D, "throw AttemptFailure.unanswered(reason: reason)", "throw AttemptFailure.rejected(HTTPResponse(status: .badRequest))", mode="stmt"),
    Mutant("unavailablerejected", D, "throw AttemptFailure.unavailable(response)", "throw AttemptFailure.rejected(response)", mode="stmt"),
    Mutant("transportcancelledendsretries", D, "Task.isCancelled", "true"),
    Mutant("cancelledunanswered", D, "throw CancellationError()", "throw AttemptFailure.unanswered(reason: \"cancelled\")", mode="stmt"),
    Mutant("invalidrequestretried", D, "throw AttemptFailure.invalidRequest(reason: reason)", "throw AttemptFailure.unanswered(reason: reason)", mode="stmt"),
    Mutant("cancelledrejected", D, "throw CancellationError()", "throw AttemptFailure.rejected(HTTPResponse(status: .badRequest))", mode="stmt"),
    Mutant("transientstatusrejected", D, "status.isTransient", "false"),
    Mutant("everyfailuretransient", D, "status.isTransient", "true"),
    Mutant("noservererrorretried", R, "kind == .serverError", "false"),
    Mutant("norequesttimeoutretried", R, "self == .requestTimeout", "false"),
    Mutant("notoomanyrequestsretried", R, "self == .tooManyRequests", "false"),
    Mutant("rejectionretried", R, "return false", "return try await backoff.handle(error: error, beforeRetry: beforeRetry)", mode="stmt"),
    Mutant("backoffbase3", R, "ExponentialBackoffStrategy(base: 2, maxCount: UInt(Int32.max) - 1, maxDelay: backoff.maximumDelay)", "ExponentialBackoffStrategy(base: 3, maxCount: UInt(Int32.max) - 1, maxDelay: backoff.maximumDelay)"),
    Mutant("afluentcapsooner", R, "backoff.maximumDelay", "backoff.initialDelay", nth=1),
    Mutant("retryoffbyone", R, "power.trailingZeroBitCount", "power.trailingZeroBitCount + 1"),
    # ExponentialBackoff.
    # The defaults: the first .seconds(1) is the doc comment's.
    Mutant("defaultinitial", E, "initialDelay = .seconds(1)", "initialDelay = .seconds(2)", mode="stmt"),
    Mutant("defaultmaximum", E, "maximumDelay = .seconds(60)", "maximumDelay = .seconds(61)", mode="stmt"),
    Mutant("noguard", E, "guard initialDelay > .zero, maximumDelay >= initialDelay else { throw InvalidBackoff() }", "", mode="stmt"),
    Mutant("zeroinitialallowed", E, "initialDelay > .zero", "initialDelay >= .zero"),
    Mutant("maximumequalrefused", E, "maximumDelay >= initialDelay", "maximumDelay > initialDelay"),
    Mutant("initialkeptasmaximum", E, "self.initialDelay = initialDelay", "self.initialDelay = maximumDelay", mode="stmt"),
    Mutant("maximumkeptasinitial", E, "self.maximumDelay = maximumDelay", "self.maximumDelay = initialDelay", mode="stmt"),
    Mutant("tripling", E, "delay *= 2", "delay *= 3", mode="stmt"),
    Mutant("onedoublingtoomany", E, "delay(afterDoubling: retry - 1)", "delay(afterDoubling: retry)"),
    Mutant("retryzeroallowed", E, "retry >= 1", "retry >= 0"),
    Mutant("doublingsnotcounted", E, "doublings -= 1", "doublings -= 2", mode="stmt"),
    Mutant("halfmaximum", E, "guard delay < maximumDelay - delay else { return maximumDelay }", "guard delay < maximumDelay / 2 else { return maximumDelay }", mode="stmt"),
    Mutant("uncapped", E, "guard delay < maximumDelay - delay else { return maximumDelay }", "", mode="stmt"),
    Mutant("capreturnsdelay", E, "guard delay < maximumDelay - delay else { return maximumDelay }", "guard delay < maximumDelay - delay else { return delay }", mode="stmt"),
    # The URLSession convenience init.
    Mutant("urlsessioninstrumentignored", S, """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock)""", """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: InstrumentationSystem.instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock)""", mode="stmt"),
    Mutant("urlsessionclockignored", S, """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock)""", """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: ContinuousClock())""", mode="stmt"),
    # The transport and injector, unchanged by retries.
    Mutant("invalidnametraps", I, """guard let name = HTTPField.Name(key) else {
            return
        }
        fields[name] = value""", "fields[HTTPField.Name(key)!] = value", mode="stmt"),
    Mutant("configuredfieldwins", I, "fields[name] = value", "fields[name] = fields[name] ?? value", mode="stmt"),
    Mutant("injectedappended", I, "fields[name] = value", "fields.append(HTTPField(name: name, value: value))", mode="stmt"),
    Mutant("invalidrequestasfailed", U, "error.code.meansInvalidRequest", "false"),
    Mutant("unsupportedurlfailed", U, "self == .unsupportedURL", "false"),
    Mutant("cancelledasfailed", U, "throw .cancelled", "throw .failed(reason: \"cancelled\")", mode="stmt"),
    Mutant("failedascancelled", U, "throw .failed(reason: error.failureReason)", "throw .cancelled", mode="stmt"),
    Mutant("reasondescribed", U, "throw .failed(reason: error.failureReason)", "throw .failed(reason: String(describing: error))", mode="stmt"),
    Mutant("reasonwithoutcode", U, '"\\(error.domain) \\(error.code)"', '"\\(error.domain)"'),
    Mutant("cancellationignored", U, "Task.isCancelled || error is CancellationError", "error is CancellationError"),
]
