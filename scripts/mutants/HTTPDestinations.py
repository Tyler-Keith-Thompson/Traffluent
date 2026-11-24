# Planted bugs for HTTPDestinations; run with `just mutate HTTPDestinations`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/HTTPDestinations/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Dropping or changing a `logger.error` in `Outcome.log()`, or logging a cancelled send: logs are
#   for developers, and tests don't pin them (AGENTS.md). What each outcome is, which decides what
#   is logged, is pinned through `send(_:)`.
# - Leaving out `|| error is CancellationError` in URLSessionTransport: a CancellationError comes
#   only from a cancelled task, which `Task.isCancelled` already catches.
# - Anything in URLSession+UploadWithoutCancelling.swift: it compiles only with FoundationNetworking
#   (Linux), and mutation runs on the Mac, where the file is empty. URLSessionTransportTests pin it
#   under `swift test` on Linux, cancelRacingRefusal among them.
#
# `injectedaftercontenttype` comes before the other mutants of those lines, which would otherwise
# wrap them apart; its schema then holds their text twice, so they pick the original with `nth=1`.

TESTS = ["HTTPDestinationsTests"]

D = "HTTPDestination.swift"
U = "URLSessionTransport.swift"
I = "HTTPFieldsInjector.swift"
S = "HTTPDestination+URLSessionTransport.swift"

MUTANTS = [
    Mutant("nosend", D, "await send(batch).log()", "", mode="stmt"),
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
    Mutant("everystatusdelivered", D, "return response.status.kind == .successful ? .delivered(response) : .rejected(response)", "return .delivered(response)", mode="stmt"),
    Mutant("nostatusdelivered", D, "return response.status.kind == .successful ? .delivered(response) : .rejected(response)", "return .rejected(response)", mode="stmt"),
    Mutant("below300delivered", D, "return response.status.kind == .successful ? .delivered(response) : .rejected(response)", "return response.status.code < 300 ? .delivered(response) : .rejected(response)", mode="stmt"),
    Mutant("only200delivered", D, "return response.status.kind == .successful ? .delivered(response) : .rejected(response)", "return response.status.code == 200 ? .delivered(response) : .rejected(response)", mode="stmt"),
    Mutant("encodingerrorlost", D, "return .notEncoded(error)", "return .notSent(.failed(reason: String(describing: error)))", mode="stmt"),
    Mutant("transporterrorlost", D, "return .notSent(error)", "return .notSent(.cancelled)", mode="stmt"),
    Mutant("noinjection", D, "instrument.inject(first.context, into: &request.headerFields, using: HTTPFieldsInjector())", "", mode="stmt", nth=1),
    Mutant("lastrecordcontext", D, "first.context", "batch[batch.count - 1].context", nth=1),
    Mutant("firstrecordindexed", D, "batch.first", "Optional(batch[0])", nth=1),
    Mutant("instrumentignored", D, "self.instrument = instrument", "self.instrument = InstrumentationSystem.instrument", mode="stmt"),
    Mutant("urlsessioninstrumentignored", S, """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: instrument,
            transport: URLSessionTransport(),
            encoder: encoder)""", """self.init(
            endpoint: endpoint,
            headerFields: headerFields,
            instrument: InstrumentationSystem.instrument,
            transport: URLSessionTransport(),
            encoder: encoder)""", mode="stmt"),
    Mutant("invalidnametraps", I, """guard let name = HTTPField.Name(key) else {
            return
        }
        fields[name] = value""", "fields[HTTPField.Name(key)!] = value", mode="stmt"),
    Mutant("configuredfieldwins", I, "fields[name] = value", "fields[name] = fields[name] ?? value", mode="stmt"),
    Mutant("injectedappended", I, "fields[name] = value", "fields.append(HTTPField(name: name, value: value))", mode="stmt"),
    Mutant("cancelledasfailed", U, "throw .cancelled", "throw .failed(reason: \"cancelled\")", mode="stmt"),
    Mutant("failedascancelled", U, "throw .failed(reason: error.failureReason)", "throw .cancelled", mode="stmt"),
    Mutant("reasondescribed", U, "throw .failed(reason: error.failureReason)", "throw .failed(reason: String(describing: error))", mode="stmt"),
    Mutant("reasonwithoutcode", U, '"\\(error.domain) \\(error.code)"', '"\\(error.domain)"'),
    Mutant("cancellationignored", U, "Task.isCancelled || error is CancellationError", "error is CancellationError"),
]
