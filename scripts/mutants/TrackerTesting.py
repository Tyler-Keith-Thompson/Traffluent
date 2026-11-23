# Planted bugs for TrackerTesting; run with `just mutate TrackerTesting`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/TrackerTesting/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent to the original.
#
# The helper's own logic only: binding the tracker for the body, handing the body that tracker,
# finishing it before reading, the order read, and the typed and named views of the records.
# Calls sharing a tracker isn't planted: a shared tracker couldn't be finished per call, so the
# bug is a hang the finish mutant already stands for.
#
# Known equivalent mutants (they survive by design): none.

TESTS = ["TrackerTestingTests"]

W = "WithRecordingTracker.swift"
R = "TrackerRecording.swift"

SYNC_RETURN = "    return await TrackerRecording(value: value, records: tracker.finishedRecords())"
SYNC_BIND = "    let value = try withTracker(tracker) { () throws(Failure) -> Value in try body(tracker) }\n" + SYNC_RETURN
ASYNC_BIND = "    let value = try await withTracker(tracker) { () async throws(Failure) -> Value in try await body(tracker) }\n" + SYNC_RETURN

MUTANTS = [
    # The tracker is never bound, so events tracked through Tracker.current go to the no-op one.
    Mutant("unboundsync", W, SYNC_BIND, "    let value = try body(tracker)\n" + SYNC_RETURN, mode="stmt"),
    Mutant("unboundasync", W, ASYNC_BIND, "    let value = try await body(tracker)\n" + SYNC_RETURN, mode="stmt"),
    # The body is handed a tracker other than the one recorded.
    Mutant("othertrackersync", W, SYNC_BIND, "    let value = try withTracker(tracker) { () throws(Failure) -> Value in try body(Tracker()) }\n" + SYNC_RETURN, mode="stmt"),
    Mutant("othertrackerasync", W, ASYNC_BIND, "    let value = try await withTracker(tracker) { () async throws(Failure) -> Value in try await body(Tracker()) }\n" + SYNC_RETURN, mode="stmt"),
    # Flushed rather than finished: the records never end, so reading them waits forever.
    Mutant("flushednotfinished", W, "        await finish()", "        await flush()", mode="stmt"),
    Mutant("reversed", W, "        return records", "        return records.reversed()", mode="stmt"),
    Mutant("firstoftypeonly", R, "records.compactMap { $0.event as? E }", "Array(records.compactMap { $0.event as? E }.prefix(1))"),
    Mutant("typenamesnotnames", R, "records.map(\\.name)", "records.map { String(describing: type(of: $0.event)) }"),
]
