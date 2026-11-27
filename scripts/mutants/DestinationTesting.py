# Planted bugs for DestinationTesting; run with `just mutate DestinationTesting`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/DestinationTesting/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent.
#
# A mutant here weakens a check, so a destination that breaks the rule passes: the kit's own tests
# (DestinationTestingTests) run it against destinations with a planted flaw each, which the check
# must catch, and PostHog's run it against a conforming one, which it must pass.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The issue texts: tests pin that an issue is recorded, not its words.
# - The trace check's record tracked in a span (`context: span.context`): the in-memory tracer
#   records an injection whatever the context, so a record outside any span still fails a
#   destination that asks the tracer to inject; the span makes its header fields hold a trace ID
#   too, which a real tracer needs.
#
# Left out because a mutant switch can't hold the `let` it binds: `withTracer` around the trace
# check's send. Without it no tracer is active, and forwardsTraceContext and writesTraceIntoBody
# would record no issue.
# - The consent check's arms for a denied and an unaccepted event, and the retry and rejection
#   checks' counts and reports: the factory returns an `HTTPDestination`, whose retry rule is the
#   library's and whose records the tracker and `accepting(_:)` have already gated, so no vendor's
#   destination can break those rules. The arms guard against a regression in the library itself,
#   which HTTPDestinationsTests and TrackersTests pin.
#
# Left out because they hang rather than fail: the script read from its first answer for every
# request, and an empty script answering with no response. Either makes a check's destination
# retry until the suite's time limit. ScriptedTransportTests pin both.

TESTS = ["DestinationTestingTests", "PostHogEncodingTests"]

T = "ScriptedTransport.swift"
C = "DestinationConformance.swift"
S = "DestinationSetup.swift"

MUTANTS = [
    # The transport.
    Mutant("requestsnotkept", T, "sent.append(SentRequest(request: request, body: body))", "", mode="stmt"),
    # Fixtures.
    Mutant("fixtureignored", C, "actual != expected", "false"),
    Mutant("missingfixturepasses", C, 'Issue.record("No fixture \\(name).\\(pathExtension) in \\(bundle.bundlePath). The requests sent were:\\n\\(bodyText(actual))", sourceLocation: sourceLocation)', "", mode="stmt"),
    Mutant("fixturenonewline", C, 'actual.append(UInt8(ascii: "\\n"))', "", mode="stmt"),
    # Sensitive values.
    Mutant("defaultsensitivepasses", C, "defaultText.contains(secret)", "false"),
    Mutant("optedinsensitivepasses", C, "!optedInText.contains(secret)", "false"),
    Mutant("redactedoptedinpasses", C, "optedInRedactedText.contains(secret)", "false"),
    # Consent.
    Mutant("grantednotrequired", C, "!text.contains(ConformanceAnalyticsEvent.name)", "false"),
    # Oversized records.
    Mutant("oversizedunreportedpasses", C, "skippedIDs != [oversized.id]", "false"),
    Mutant("oversizedsentpasses", C, "sent.requests.contains(where: { $0.body.count > labelByteCount })", "false"),
    Mutant("oversizedundersized", C, 'String(repeating: "x", count: labelByteCount)', 'String(repeating: "x", count: 1)'),
    Mutant("oversizedalwaysunchecked", C, "labelByteCount <= 64 << 20", "labelByteCount <= 0"),
    # Trace context.
    Mutant("traceheaderpasses", C, "request.request.headerFields.contains(where: { traceFields.contains($0.name.canonicalName) })", "false"),
    Mutant("traceinjectionpasses", C, "!tracer.performedContextInjections.isEmpty", "false"),
    Mutant("tracenothingsentpasses", C, 'Issue.record("The destination sent nothing for a record tracked in a span", sourceLocation: sourceLocation)', "", mode="stmt"),
    # Retries and rejections: the script's statuses.
    Mutant("retriednotfailing", C, "[failure, .status(.ok)]", "[ScriptedTransport.Answer.status(.ok)]"),
    Mutant("rejectednotrejecting", C, "[.status(status)]", "[ScriptedTransport.Answer.status(.ok)]"),
    # Timestamps: every check's records at the setup's timestamp.
    Mutant("consentrecordsnow", C, "Tracker(consent: consent, now: { [timestamp] in timestamp })", "Tracker(consent: consent)"),
    Mutant("checkstimestampdefault", C, "self.timestamp = timestamp", "self.timestamp = .conformanceTimestamp", mode="stmt"),
    Mutant("setuptimestampother", S, "self.timestamp = timestamp", "self.timestamp = .distantPast", mode="stmt"),
]
