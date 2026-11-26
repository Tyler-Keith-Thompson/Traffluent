# Planted bugs for Sessions. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/Sessions/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a test,
# or a note here saying why it is equivalent to the original.
#
# They cover the decisions: the timeout's boundary and what inactivity counts from; a new session at
# the timeout; SessionStarted and SessionEnded, their keys, times and durations; each kind turned
# off while the key stays; and the identifier random and held in memory only. The events' encodings
# and the call site are pinned by tests but get no mutants: they repeat LifecycleTracking's shape.
#
# Left out: a write of the identifier to `UserDefaults.standard`. The user defaults test catches it
# under Bazel (`bazel test //Tests/SessionsTests`, checked by hand), but SwiftPM runs the tests in
# swiftpm-testing-helper, which has no bundle and so no defaults domain to write to: the mutant
# would survive here for want of a domain, not a test. The store-directory scan covers disk writes.

TESTS = ["SessionsTests"]

L = "SessionTimeline.swift"
R = "SessionRotation.swift"
S = "Session.swift"
E = "Enricher+Sessions.swift"
M = "Sampler+Sessions.swift"

START = "return EventRecord(event: SessionStarted(), timestamp: session.start, sourceLocation: callSite, context: context)"
GAP = "Duration.seconds(timestamp.timeIntervalSince(session.lastActivity)) < timeout"

MUTANTS = [
    # SessionKey as a UUIDv7 (TRAF-74).
    Mutant("v7noversion", "UUID+Version7.swift", "bytes[6] = 0x70 | (bytes[6] & 0x0F)", "bytes[6] = 0x40 | (bytes[6] & 0x0F)", mode="stmt"),
    Mutant("v7novariant", "UUID+Version7.swift", "bytes[8] = 0x80 | (bytes[8] & 0x3F)", "bytes[8] = 0xC0 | (bytes[8] & 0x3F)", mode="stmt"),
    Mutant("v7littleendian", "UUID+Version7.swift", "timestamp >> (8 * (5 - index))", "timestamp >> (8 * index)"),
    Mutant("v7rounded", "UUID+Version7.swift", "(date.timeIntervalSince1970 * 1_000).rounded(.down)", "(date.timeIntervalSince1970 * 1_000).rounded()"),
    Mutant("v7noclamp", "UUID+Version7.swift", "Swift.max(milliseconds, 0)", "milliseconds"),
    # The 12 random bits after the version (bytes 6-7) aren't pinned: two sessions share them
    # once in 4,096, so a test that they differ would flake. A mutant zeroing them would survive,
    # so none is planted.
    Mutant("v7norandom", "UUID+Version7.swift", "generator.next() as UInt64", "UInt64(0)", nth=1),

    # The timeout's boundary, and inactivity measured from the session's last event.
    Mutant("timeoutboundary", L, GAP, GAP.replace("< timeout", "<= timeout")),
    Mutant("neverrotates", L, GAP, "true"),
    Mutant("fromfirstevent", L, "        session.lastActivity = max(session.lastActivity, timestamp)", "        ()", mode="stmt"),
    Mutant("lastmovesback", L, "max(session.lastActivity, timestamp)", "timestamp"),
    Mutant("defaulttimeout", E, ".seconds(30 * 60)", ".seconds(30 * 60 + 1)"),
    Mutant("zerotimeoutallowed", E, "timeout > .zero", "timeout >= .zero"),
    # SessionStarted and SessionEnded.
    Mutant("nofirststart", R, "            return kinds.contains(.started) ? [startRecord(of: session, in: context)] : []", "            return []", mode="stmt"),
    Mutant("norotatedstart", R, "                records.append(startRecord(of: started, in: context))", "                ()", mode="stmt"),
    Mutant("noend", R, "                records.append(endRecord(of: ended, in: context))", "                ()", mode="stmt"),
    Mutant("startbeforeend", R, "            return records", "            return records.reversed()", mode="stmt"),
    # The third: the first two set the record's own key, in the continued and started cases.
    Mutant("endwithoutkey", R, "context[SessionKey.self] = session.id", "()", mode="stmt", nth=3),
    Mutant("endatstart", R, "session.lastActivity", "session.start"),
    Mutant("zeroduration", S, ".seconds(lastActivity.timeIntervalSince(start))", ".zero"),
    # Each kind turned off, the key kept.
    Mutant("startkindignored", R, "kinds.contains(.started)", "true", nth=0),
    Mutant("endkindignored", R, "kinds.contains(.ended)", "true"),
    # The second: the started case's own key.
    Mutant("nokindsnokey", R, "record.context[SessionKey.self] = session.id", "if !kinds.isEmpty { record.context[SessionKey.self] = session.id }", mode="stmt", nth=1),
    # Random, and held in memory only.
    Mutant("constantid", R, "{ UUID(version7At: timestamp) }", "{ UUID(uuid: (0, 0, 0, 0, 0, 0, 0x70, 0, 0x80, 0, 0, 0, 0, 0, 0, 0)) }"),
    # A session record's identifier is its own, never the session's key. Only SessionStarted's:
    # SessionEnded's statement holds endatstart's text, and its record takes the same default.
    Mutant("startidissessionkey", R, START, START.replace("EventRecord(event:", "EventRecord(id: session.id, event:"), mode="stmt"),
    # Sampling whole sessions: by the session's key, through the caller's predicate.
    Mutant("sessionpredicateignored", M, ".grouped(by: SessionKey.self, where: selects, rate: rate)", ".grouped(by: SessionKey.self, rate: rate)"),
]
