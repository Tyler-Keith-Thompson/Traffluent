# Planted bugs for HTTPDestinations; run with `just mutate HTTPDestinations`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/HTTPDestinations/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - ExponentialBackoff's `jitter: Jitter = .full` defaults: a public function's default argument
#   can't call the internal __mutant switch, so they can't be planted; fullJitterByDefault pins them.
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
# - The dictionary of contexts keeping the last of two records of one identifier rather than the
#   first: a batch holds one record of each identifier.
# - The `.cancelled` arm's `return` in `receive(_:)` as `break`, going on to the batch's next
#   request: that request's unit of work starts in a cancelled task, which Afluent ends before it
#   calls the transport, so nothing more is sent or reported either way (cancelledMidBatch pins
#   that). The `return` saves the later requests' setup.
#
# Not pinned: URLSessionTransport's `.badURL` and `.appTransportSecurityRequiresSecureConnection`
# as invalid requests (no URL reliably produces either on both macOS and Linux in a test; the
# `.unsupportedURL` case beside them is pinned with a `foo://` URL). And the URLSession
# convenience init passing `backoff:` and `randomNumberGenerator:` on (urlsessionbackoffignored and
# urlsessiongeneratorignored would survive). Its sends go to a real URLSession, and with no server to count requests, a test
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

# The deadline mutants that retry a request past its deadline (deadlineretried, deadlinenanpasses,
# and the ones that sleep a backoff after a send fails past it, *pastdeadlineretried and
# faileddeadlinenanpasses), and faileddeadlineexclusive, which reports one the test waits to see
# sleep, leave its tests waiting on a test clock nobody advances, so they are caught by the
# suite's time limit.
#
# The backoff mutants that wait longer or stop retrying (backofftripled, retriescapped,
# uncappedwaits, afluentinitialismaximum) are caught both ways. waitsMatchDelayBeforeRetry runs on
# a clock whose sleeps return at once, so it fails an assertion on the waits or the sleep count.
# Its TestClock siblings advance the clock by the expected waits only, so a longer wait or a
# missing attempt leaves them waiting, and the suite's time limit catches them. afluentcapsooner,
# whose waits are shorter, fails an assertion on the waits in both.
MUTANTS = [
    Mutant("methodput", D, "request = HTTPRequest(method: .post, url: endpoint, headerFields: headerFields)", "request = HTTPRequest(method: .put, url: endpoint, headerFields: headerFields)", mode="stmt"),
    Mutant("noheaderfields", D, "request = HTTPRequest(method: .post, url: endpoint, headerFields: headerFields)", "request = HTTPRequest(method: .post, url: endpoint)", mode="stmt"),
    Mutant("lastrecordonly", D, "encoded = try encoder.requests(for: batch)", "encoded = try encoder.requests(for: Array(batch.suffix(1)))", mode="stmt"),
    Mutant("injectedaftercontenttype", D, """if let context {
            instrument.inject(context, into: &request.headerFields, using: HTTPFieldsInjector())
        }
        request.headerFields[.contentType] = encoded.body.contentType""", """request.headerFields[.contentType] = encoded.body.contentType
        if let context {
            instrument.inject(context, into: &request.headerFields, using: HTTPFieldsInjector())
        }""", mode="stmt"),
    Mutant("nocontenttype", D, "request.headerFields[.contentType] = encoded.body.contentType", "", mode="stmt", nth=1),
    Mutant("configuredcontenttypewins", D, "request.headerFields[.contentType] = encoded.body.contentType", "request.headerFields[.contentType] = request.headerFields[.contentType] ?? encoded.body.contentType", mode="stmt", nth=1),
    Mutant("emptybody", D, "encoded.body.body", "Data()"),
    Mutant("noinjection", D, "instrument.inject(context, into: &request.headerFields, using: HTTPFieldsInjector())", "", mode="stmt", nth=1),
    # Several requests of one batch (TRAF-101).
    Mutant("lastrecordcontext", D, "request.recordIDs.first.flatMap { contexts[$0] }", "request.recordIDs.last.flatMap { contexts[$0] }"),
    Mutant("batchcontext", D, "request.recordIDs.first.flatMap { contexts[$0] }", "batch.first?.context"),
    Mutant("requestsreversed", D, "encoded.requests", "Array(encoded.requests.reversed())"),
    # The second copy is the original's, after requestsreversed's.
    Mutant("onlyfirstrequest", D, "encoded.requests", "Array(encoded.requests.prefix(1))", nth=1),
    Mutant("skippednotreported", D, "reporter.report(.skipped(skipped))", "", mode="stmt"),
    # An abandoned request goes on to the batch's next request.
    Mutant("abandonedstops", D, 'logger.error("Stopped sending a request, whose wait before the next attempt threw: \\(error)")', "return", mode="stmt"),
    Mutant("instrumentignored", D, "self.instrument = instrument", "self.instrument = InstrumentationSystem.instrument", mode="stmt"),
    # Outcomes and reports.
    # A strategy that never retries, in place of the destination's. It replaces the assignment in
    # the initializer: `send`'s `let response = …` is a declaration, which a stmt mutant can't
    # wrap, and an expr mutant on `retryStrategy()` gives `.retry(_:)` an `any RetryStrategy` from
    # the schema's ternary, which Swift won't open for its generic parameter.
    Mutant("noretry", D, "retryStrategy = { TransientFailureRetry(backoff, clock: clock, generator: generator) }", "retryStrategy = { RetryByCountStrategy(retryCount: 0) }", mode="stmt"),
    Mutant("deliveredascancelled", D, "return .delivered(response)", "return .cancelled", mode="stmt"),
    Mutant("rejectedascancelled", D, "return .rejected(response)", "return .cancelled", mode="stmt"),
    Mutant("rejectionnotreported", D, "reporter.report(.rejected(status: response.status, recordIDs: request.recordIDs))", "", mode="stmt"),
    Mutant("rejectionstatuslost", D, "reporter.report(.rejected(status: response.status, recordIDs: request.recordIDs))", "reporter.report(.rejected(status: .badRequest, recordIDs: request.recordIDs))", mode="stmt"),
    Mutant("rejectionidsofbatch", D, "reporter.report(.rejected(status: response.status, recordIDs: request.recordIDs))", "reporter.report(.rejected(status: response.status, recordIDs: batch.map(\\.id)))", mode="stmt"),
    Mutant("invalidrequestascancelled", D, "return .invalidRequest(reason)", "return .cancelled", mode="stmt"),
    Mutant("invalidrequestnotreported", D, "reporter.report(.invalidRequest(reason: reason, recordIDs: request.recordIDs))", "", mode="stmt"),
    Mutant("invalidrequestreasonlost", D, "reporter.report(.invalidRequest(reason: reason, recordIDs: request.recordIDs))", "reporter.report(.invalidRequest(reason: \"\", recordIDs: request.recordIDs))", mode="stmt"),
    Mutant("invalidrequestidslost", D, "reporter.report(.invalidRequest(reason: reason, recordIDs: request.recordIDs))", "reporter.report(.invalidRequest(reason: reason, recordIDs: []))", mode="stmt"),
    # The three mutants before this one that return `.cancelled` sit above it in the file, so the
    # original `return .cancelled` (under `catch is CancellationError`) is the fourth.
    Mutant("cancellationabandoned", D, "return .cancelled", "return .abandoned(CancellationError())", mode="stmt", nth=3),
    Mutant("abandonedascancelled", D, "return .abandoned(error)", "return .cancelled", mode="stmt"),
    Mutant("encodingnotreported", D, "reporter.report(.notEncoded(error, recordIDs: batch.map(\\.id)))", "", mode="stmt"),
    Mutant("encodingidslost", D, "reporter.report(.notEncoded(error, recordIDs: batch.map(\\.id)))", "reporter.report(.notEncoded(error, recordIDs: []))", mode="stmt"),
    Mutant("reportsneverend", D, "reports.finish()", "", mode="stmt"),
    # Attempts and retries.
    Mutant("backoffignored", D, "retryStrategy = { TransientFailureRetry(backoff, clock: clock, generator: generator) }", "retryStrategy = { TransientFailureRetry(ExponentialBackoff(), clock: clock, generator: generator) }", mode="stmt"),
    Mutant("clockignored", D, "retryStrategy = { TransientFailureRetry(backoff, clock: clock, generator: generator) }", "retryStrategy = { TransientFailureRetry(backoff, clock: ContinuousClock(), generator: generator) }", mode="stmt"),
    Mutant("strategysharedacrossbatches", D, "retryStrategy = { TransientFailureRetry(backoff, clock: clock, generator: generator) }", "let strategy = TransientFailureRetry(backoff, clock: clock, generator: generator)\n        retryStrategy = { strategy }", mode="stmt"),
    Mutant("everystatusdelivered", D, "status.kind == .successful", "true"),
    Mutant("nostatusdelivered", D, "status.kind == .successful", "false"),
    Mutant("below300delivered", D, "status.kind == .successful", "status.code < 300"),
    Mutant("only200delivered", D, "status.kind == .successful", "status.code == 200"),
    Mutant("unansweredrejected", D, """throw retried(.unanswered(reason: reason), "A batch got no response, so it will be sent again: \\(reason)")""", "throw AttemptFailure.rejected(HTTPResponse(status: .badRequest))", mode="stmt"),
    Mutant("unavailablerejected", D, """throw retried(.unavailable(response.head), "The endpoint answered a batch with \\(status), so it will be sent again")""", "throw AttemptFailure.rejected(response.head)", mode="stmt"),
    Mutant("transportcancelledendsretries", D, "Task.isCancelled", "true"),
    Mutant("cancelledunanswered", D, "throw CancellationError()", "throw AttemptFailure.unanswered(reason: \"cancelled\")", mode="stmt"),
    Mutant("invalidrequestretried", D, "throw AttemptFailure.invalidRequest(reason: reason)", "throw AttemptFailure.unanswered(reason: reason)", mode="stmt"),
    Mutant("cancelledrejected", D, "throw CancellationError()", "throw AttemptFailure.rejected(HTTPResponse(status: .badRequest))", mode="stmt"),
    Mutant("transientstatusrejected", D, "status.isTransient", "false"),
    Mutant("everyfailuretransient", D, "status.isTransient", "true"),
    # The encoder's transient statuses (BatchEncoder.transientStatuses, TransientStatus). The
    # mutants that drop them leave encoderTransientStatusRetried waiting for an attempt that never
    # comes, so the suite's time limit catches them.
    Mutant("encoderstatusesignored", D, "transientStatuses.contains(status)", "false"),
    Mutant("everyfailureencodertransient", D, "transientStatuses.contains(status)", "true"),
    Mutant("encoderstatusesunread", D, "Set(Encoding.transientStatuses.map(\\.status))", "[]"),
    Mutant("anyunsuccessfultaken", "TransientStatus.swift", "status.kind == .clientError || status.kind == .serverError", "status.kind != .successful"),
    Mutant("clienterrorrefused", "TransientStatus.swift", "status.kind == .clientError", "false"),
    Mutant("servererrorrefused", "TransientStatus.swift", "status.kind == .serverError", "false"),
    Mutant("statusreplaced", "TransientStatus.swift", "self.status = status", "self.status = HTTPResponse.Status(code: 400)", mode="stmt"),
    Mutant("noservererrorretried", R, "kind == .serverError", "false"),
    Mutant("norequesttimeoutretried", R, "self == .requestTimeout", "false"),
    Mutant("notoomanyrequestsretried", R, "self == .tooManyRequests", "false"),
    Mutant("rejectionretried", R, "return false", "return try await backoff.handle(error: error, beforeRetry: beforeRetry)", mode="stmt"),
    # Each mutant of the strategy's expression puts its own copy before the original's, so a later
    # one's `nth` skips those copies: for afluentcapsooner, backofftripled's and retriescapped's
    # (uncappedwaits' has no maxDelay); for afluentinitialismaximum, all three.
    Mutant("backofftripled", R, "ExponentialBackoffStrategy(initialDelay: backoff.initialDelay, multiplier: 2, maxDelay: backoff.maximumDelay, jitter: backoff.jitter.afluentJitter(using: generator))", "ExponentialBackoffStrategy(initialDelay: backoff.initialDelay, multiplier: 3, maxDelay: backoff.maximumDelay, jitter: backoff.jitter.afluentJitter(using: generator))"),
    Mutant("retriescapped", R, "ExponentialBackoffStrategy(initialDelay: backoff.initialDelay, multiplier: 2, maxDelay: backoff.maximumDelay, jitter: backoff.jitter.afluentJitter(using: generator))", "ExponentialBackoffStrategy(initialDelay: backoff.initialDelay, multiplier: 2, maxCount: 5, maxDelay: backoff.maximumDelay, jitter: backoff.jitter.afluentJitter(using: generator))"),
    Mutant("uncappedwaits", R, "ExponentialBackoffStrategy(initialDelay: backoff.initialDelay, multiplier: 2, maxDelay: backoff.maximumDelay, jitter: backoff.jitter.afluentJitter(using: generator))", "ExponentialBackoffStrategy(initialDelay: backoff.initialDelay, multiplier: 2, jitter: backoff.jitter.afluentJitter(using: generator))"),
    Mutant("afluentcapsooner", R, "backoff.maximumDelay", "backoff.initialDelay", nth=2),
    Mutant("afluentinitialismaximum", R, "backoff.initialDelay", "backoff.maximumDelay", nth=3),
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
    # Jitter (TRAF-124). seededWaits and waitsMatchReference catch the full-jitter mutants; the
    # tests that pin exact waits with `.none` (waitsMatchDelayBeforeRetry, defaultDelaySequence)
    # catch the ones that jitter a `.none` backoff; copiesShareGenerator catches a generator per
    # request, which replays the same first draw for every request.
    Mutant("defaultjitterunkept", E, "self.jitter = jitter", "self.jitter = .none", mode="stmt", nth=0),
    Mutant("delaysjitterunkept", E, "self.jitter = jitter", "self.jitter = .none", mode="stmt", nth=1),
    Mutant("fulljitternone", R, "BackoffJitter.full(using: generator)", "BackoffJitter.none"),
    Mutant("nonejitterfull", R, "BackoffJitter.none", "BackoffJitter.full(using: generator)", nth=0),
    # The three strategy mutants above copy the jitter argument into theirs, so the original is
    # the fourth.
    Mutant("jitterunread", R, "backoff.jitter.afluentJitter(using: generator)", "ExponentialBackoff.Jitter.full.afluentJitter(using: generator)", nth=3),
    Mutant("generatorignored", D, "SharedRandomNumberGenerator(randomNumberGenerator)", "SharedRandomNumberGenerator(SystemRandomNumberGenerator())"),
    Mutant("generatorperrequest", D, "retryStrategy = { TransientFailureRetry(backoff, clock: clock, generator: generator) }", "retryStrategy = { TransientFailureRetry(backoff, clock: clock, generator: SharedRandomNumberGenerator(randomNumberGenerator)) }", mode="stmt"),
    # A draw from a copy leaves the shared generator where it was, so every wait repeats its first
    # draw; seededWaits and copiesShareGenerator catch it.
    Mutant("drawsfromcopy", "SharedRandomNumberGenerator.swift", "box.generator.withLock { $0.next() }", "{ var copy = box.generator.withLock { $0 }; return copy.next() }()"),
    # The URLSession convenience init.
    Mutant("urlsessioninstrumentignored", S, """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            randomNumberGenerator: randomNumberGenerator,
            now: now)""", """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: InstrumentationSystem.instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            randomNumberGenerator: randomNumberGenerator,
            now: now)""", mode="stmt"),
    Mutant("urlsessionclockignored", S, """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            randomNumberGenerator: randomNumberGenerator,
            now: now)""", """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: ContinuousClock(),
            randomNumberGenerator: randomNumberGenerator,
            now: now)""", mode="stmt"),
    Mutant("urlsessionnowignored", S, """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            randomNumberGenerator: randomNumberGenerator,
            now: now)""", """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            randomNumberGenerator: randomNumberGenerator,
            now: { Date.now })""", mode="stmt"),
    # Deadlines (TRAF-134).
    Mutant("nowignored", D, "self.now = now", "self.now = { Date.now }", mode="stmt"),
    Mutant("deadlinenotpassed", D, "encoded.deadline", "nil"),
    Mutant("deadlineunchecked", D, """guard now() <= deadline else {
                throw AttemptFailure.deadlineExceeded(deadline)
            }""", "", mode="stmt"),
    # The first `now() <= deadline` is the check before an attempt, the second the one when it fails.
    Mutant("deadlineexclusive", D, "now() <= deadline", "now() < deadline", nth=0),
    Mutant("deadlinenanpasses", D, "now() <= deadline", "!(now() > deadline)", nth=0),
    Mutant("failedpastdeadlineretried", D, "!(now() <= deadline)", "deadline < .distantPast"),
    Mutant("faileddeadlineexclusive", D, "!(now() <= deadline)", "!(now() < deadline)"),
    Mutant("faileddeadlinenanpasses", D, "!(now() <= deadline)", "now() > deadline"),
    Mutant("unansweredpastdeadlineretried", D, """throw retried(.unanswered(reason: reason), "A batch got no response, so it will be sent again: \\(reason)")""", "throw AttemptFailure.unanswered(reason: reason)", mode="stmt"),
    Mutant("transportcancelledpastdeadlineretried", D, """throw retried(.unanswered(reason: "cancelled by the transport"), "A batch's send was cancelled by its transport, not the delivery, so it will be sent again")""", "throw AttemptFailure.unanswered(reason: \"cancelled by the transport\")", mode="stmt"),
    Mutant("unavailablepastdeadlineretried", D, """throw retried(.unavailable(response.head), "The endpoint answered a batch with \\(status), so it will be sent again")""", "throw AttemptFailure.unavailable(response.head)", mode="stmt"),
    Mutant("deadlineretried", D, "throw AttemptFailure.deadlineExceeded(deadline)", "throw AttemptFailure.unanswered(reason: \"past its deadline\")", mode="stmt"),
    Mutant("deadlinerejected", D, "throw AttemptFailure.deadlineExceeded(deadline)", "throw AttemptFailure.rejected(HTTPResponse(status: .badRequest))", mode="stmt"),
    Mutant("deadlinecancellationunchecked", D, "try Task.checkCancellation()", "", mode="stmt"),
    Mutant("deadlineascancelled", D, "return .deadlineExceeded(deadline)", "return .cancelled", mode="stmt", nth=0),
    Mutant("deadlinenotreported", D, "reporter.report(.deadlineExceeded(deadline: deadline, recordIDs: request.recordIDs))", "", mode="stmt"),
    Mutant("deadlineidsofbatch", D, "reporter.report(.deadlineExceeded(deadline: deadline, recordIDs: request.recordIDs))", "reporter.report(.deadlineExceeded(deadline: deadline, recordIDs: batch.map(\\.id)))", mode="stmt"),
    Mutant("deadlinelost", D, "reporter.report(.deadlineExceeded(deadline: deadline, recordIDs: request.recordIDs))", "reporter.report(.deadlineExceeded(deadline: .distantPast, recordIDs: request.recordIDs))", mode="stmt"),
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
    # What a 2xx answer's body says (TRAF-123).
    Mutant("outcomeignored", D, "return try delivered(response)", "return response.head", mode="stmt"),
    Mutant("rejectedinbodydelivered", D, "throw .rejectedInBody(response.head, reason: reason)", "return response.head", mode="stmt"),
    Mutant("rejectedinbodyasrejected", D, "throw .rejectedInBody(response.head, reason: reason)", "throw .rejected(response.head)", mode="stmt"),
    Mutant("transientinbodydelivered", D, """throw retried(.unavailable(response.head), "The endpoint answered a batch with \\(response.head.status), but its body says it stored nothing for now, so it will be sent again: \\(reason)")""", "return response.head", mode="stmt"),
    Mutant("transientinbodyrejected", D, """throw retried(.unavailable(response.head), "The endpoint answered a batch with \\(response.head.status), but its body says it stored nothing for now, so it will be sent again: \\(reason)")""", "throw .rejectedInBody(response.head, reason: reason)", mode="stmt"),
    Mutant("transientinbodypastdeadlineretried", D, """throw retried(.unavailable(response.head), "The endpoint answered a batch with \\(response.head.status), but its body says it stored nothing for now, so it will be sent again: \\(reason)")""", "throw AttemptFailure.unavailable(response.head)", mode="stmt"),
    Mutant("rejectedinbodycaughtasrejected", D, "return .rejectedInBody(response, reason: reason)", "return .rejected(response)", mode="stmt"),
    Mutant("rejectedinbodynotreported", D, "reporter.report(.rejectedInBody(status: response.status, reason: reason, recordIDs: request.recordIDs))", "", mode="stmt"),
    Mutant("rejectedinbodyreasonlost", D, "reporter.report(.rejectedInBody(status: response.status, reason: reason, recordIDs: request.recordIDs))", "reporter.report(.rejectedInBody(status: response.status, reason: \"\", recordIDs: request.recordIDs))", mode="stmt"),
    Mutant("rejectedinbodystatusok", D, "reporter.report(.rejectedInBody(status: response.status, reason: reason, recordIDs: request.recordIDs))", "reporter.report(.rejectedInBody(status: .ok, reason: reason, recordIDs: request.recordIDs))", mode="stmt"),
    Mutant("rejectedinbodyreportreturns", D, "reporter.report(.rejectedInBody(status: response.status, reason: reason, recordIDs: request.recordIDs))", "return", mode="stmt"),
    Mutant("rejectedinbodyidsofbatch", D, "reporter.report(.rejectedInBody(status: response.status, reason: reason, recordIDs: request.recordIDs))", "reporter.report(.rejectedInBody(status: response.status, reason: reason, recordIDs: batch.map(\\.id)))", mode="stmt"),
    Mutant("rejectedinbodyretried", R, "return false", """if case .rejectedInBody = error as? AttemptFailure {
                return try await backoff.handle(error: error, beforeRetry: beforeRetry)
            }
            return false""", mode="stmt"),
    Mutant("responsebodydropped", U, "return HTTPTransportResponse(head: head, body: responseBody)", "return HTTPTransportResponse(head: head, body: Data())", mode="stmt"),
    # The encoder's note of each 2xx answer (TRAF-155).
    Mutant("didreceiveskipped", D, "encoder.didReceive(response, for: encoded)", "", mode="stmt"),
]
