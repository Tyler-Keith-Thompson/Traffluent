# Planted bugs for Trackers; run with `just mutate Trackers`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Trackers/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Dropping `waiter.id == call` from stopWaiting: it matters only when a cancellation reaches a
#   reader after its record was handed over and before its wait returns, and another reader has
#   started waiting in between. No test can place a cancellation inside that window: the reader's
#   own task is the one that would have to run in it.
# - Dropping deinit's cancellation of the read task: a tracker dropped while a read waits then keeps
#   one suspended task and its subscription alive, which no test can observe without inspecting
#   the process's tasks.
# - `file: file` swapped for `file: fileID` in `track`'s defaults: in the Swift 6 language mode
#   `#file` is `#fileID`. The explicit-location test still catches the swap in the record's
#   initializer arguments (filefromfileid below).

TESTS = ["TrackersTests"]

T = "Tracker.swift"
W = "WithTracker.swift"
S = "Subscription.swift"
N = "Enricher.swift"

# The record track builds, to send (and write to its store, if any). Expressions rather than
# statements: a mutated `let` would be scoped to its branch.
SEND = "EventRecord(event: event, timestamp: timestamp, sourceLocation: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column), context: context)"

MUTANTS = [
    Mutant("currentignoresbinding", T, "bound ?? .noOp", ".noOp"),
    Mutant("syncunbound", W, "return try Tracker.$bound.withValue(tracker, operation: operation)", "return try operation()", mode="stmt"),
    Mutant("asyncunbound", W, "return try await Tracker.$bound.withValue(tracker, operation: operation)", "return try await operation()", mode="stmt"),
    Mutant("defaultnow", T, "Date.now", "Date.distantPast", nth=0),
    Mutant("fixedtimestamp", T, "now()", "Date(timeIntervalSince1970: 0)"),
    Mutant("nosend", T, "subscription.send(store?.append(record) ?? record)", "", mode="stmt"),
    # Each swaps one field of the source location; the original expression stays in the innermost
    # else branch, so every one finds it.
    Mutant("filefromfileid", T, SEND, SEND.replace("file: file,", "file: fileID,")),
    Mutant("fileidfromfile", T, SEND, SEND.replace("fileID: fileID,", "fileID: file,")),
    Mutant("functionfromfile", T, SEND, SEND.replace("function: function,", "function: file,")),
    Mutant("ownfunction", T, SEND, SEND.replace("function: function,", "function: #function,")),
    Mutant("linefromcolumn", T, SEND, SEND.replace("line: line,", "line: column,")),
    Mutant("ownline", T, SEND, SEND.replace("line: line,", "line: #line,")),
    Mutant("columnfromline", T, SEND, SEND.replace("column: column)", "column: line)")),
    Mutant("contextignored", T, "ServiceContext.current ?? .topLevel", "ServiceContext.topLevel"),
    Mutant("enrichersskipped", T, "enricher(&context)", "", mode="stmt"),
    Mutant("enrichersreversed", T, "self.enrichers = enrichers", "self.enrichers = enrichers.reversed()", mode="stmt"),
    Mutant("enricherinert", N, "enrich(&context)", "", mode="stmt"),
    # A finish that does nothing leaves every read waiting, so the suites' time limit catches it.
    Mutant("nofinish", T, "subscription.finish()", "", mode="stmt"),
    Mutant("subjectnotfinished", S, "subject.send(completion: .finished)", "", mode="stmt"),
    Mutant("subscriptionnotsent", S, "subject.send(record)", "", mode="stmt"),
    # A reader cancelled before it waits attaches anyway, after its handler ran: it waits for ever.
    Mutant("cancelledwaitattaches", S, "guard !Task.isCancelled else { return .some(nil) }", "", mode="stmt"),
    # A cancelled reader's waiter stays, so the next reader finds it still waiting and traps.
    Mutant("cancelledwaiterkept", S, "reads.state = .reading(waiter: nil)", "", mode="stmt"),
    Mutant("cancellednotresumed", S, "stopped?.continuation.resume(returning: nil)", "", mode="stmt"),
    # Taking over a read in flight traps as if its cancelled reader still waited.
    Mutant("takeovertraps", S, "reads.state = .reading(waiter: waiter)", 'preconditionFailure("taken over")', mode="stmt", nth=1),
    # A result no reader waited for is dropped rather than kept.
    Mutant("unclaimedresultdropped", S, "reads.state = .read(record, iterator)", "reads.state = .idle(iterator)", mode="stmt"),
    Mutant("waiterresultdropped", S, "waiter?.continuation.resume(returning: record)", "waiter?.continuation.resume(returning: nil)", mode="stmt"),
    Mutant("unclaimedresultnotgiven", S, "return .some(record)", "return .some(nil)", mode="stmt"),
    Mutant(
        "concurrentreadallowed", S,
        'preconditionFailure("A tracker\'s records are read by one task at a time")',
        "return .some(nil)",
        mode="stmt",
    ),
]
