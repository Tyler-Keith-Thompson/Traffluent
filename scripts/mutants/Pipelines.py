# Planted bugs for Pipelines; run with `just mutate Pipelines`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Pipelines/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The default clock (ContinuousClock) swapped for SuspendingClock: the two differ only while the
#   device sleeps, which no test can arrange.
# - The default-strategy init's `batchBufferLimit` default (100) isn't planted: pinning it takes
#   another hundred stuck batches through a strategy that flushes every 20 events. It is the same
#   literal as the other init's, which defaultbufferlimit covers.
# - `file: file` swapped for `file: fileID` in `track`'s defaults: in the Swift 6 language mode
#   `#file` is `#fileID`. The explicit-location test still catches the swap in the record's
#   initializer arguments (filefromfileid below).

TESTS = ["PipelinesTests"]

P = "Pipeline.swift"
S = "Subscription.swift"

# track's one statement that sends the record.
SEND = "subject.send(EventRecord(event: event, timestamp: timestamp, sourceLocation: SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column)))"

MUTANTS = [
    Mutant("defaulttimeonotherclock", P, ".time(interval: .seconds(30), clock: clock)", ".time(interval: .seconds(30), clock: ContinuousClock())"),
    Mutant("defaultcount", P, ".count(20)", ".count(19)"),
    # defaulttimeonotherclock leaves two copies; the second is the original's.
    Mutant("defaultinterval", P, ".seconds(30)", ".seconds(31)", nth=1),
    Mutant("defaultstrategynow", P, "Date.now", "Date.distantPast", nth=0),
    # defaultstrategynow leaves the first init's in a ternary; the second init's comes after.
    Mutant("customstrategynow", P, "Date.now", "Date.distantPast", nth=1),
    # The custom-strategy init's default; see the note above on the other init's.
    Mutant("defaultbufferlimit", P, "100", "99", nth=1),
    Mutant("bufferlimitzeroallowed", P, "batchBufferLimit >= 1", "batchBufferLimit >= 0"),
    Mutant("bufferonemore", P, ".bufferingNewest(batchBufferLimit)", ".bufferingNewest(batchBufferLimit + 1)"),
    Mutant("nodestinations", P, "self.destinations = destinations", "self.destinations = []", mode="stmt"),
    Mutant("strategyignored", P, "self.strategy = strategy", "self.strategy = CountBatchStrategy<EventRecord>(1)", mode="stmt"),
    Mutant("fixedtimestamp", P, "now()", "Date(timeIntervalSince1970: 0)"),
    Mutant("nosend", P, SEND, "", mode="stmt"),
    # Each swaps one field of the source location; the original statement stays in the innermost
    # else branch, so every one finds it.
    Mutant("filefromfileid", P, SEND, SEND.replace("file: file,", "file: fileID,"), mode="stmt"),
    Mutant("fileidfromfile", P, SEND, SEND.replace("fileID: fileID,", "fileID: file,"), mode="stmt"),
    Mutant("functionfromfile", P, SEND, SEND.replace("function: function,", "function: file,"), mode="stmt"),
    Mutant("linefromcolumn", P, SEND, SEND.replace("line: line,", "line: column,"), mode="stmt"),
    Mutant("columnfromline", P, SEND, SEND.replace("column: column)", "column: line)"), mode="stmt"),
    Mutant("nofinish", P, "subject.send(completion: .finished)", "", mode="stmt"),
    # Inside the defer: wrapping the defer itself in the schema's if/else would run it at once.
    Mutant("norelease", P, "subscription.release()", "", mode="stmt"),
    Mutant("firstdestinationonly", P, "for buffer in buffers { buffer.yield(batch) }", "buffers.first?.yield(batch)", mode="stmt"),
    Mutant("nodelivery", P, "await destination.receive(batch)", "", mode="stmt"),
    Mutant("buffersneverfinish", P, "for buffer in buffers { buffer.finish() }", "", mode="stmt"),
    Mutant(
        "concurrentrunallowed", S,
        'preconditionFailure("A pipeline runs one run at a time")',
        "let finished = PassthroughSubject<EventRecord>()\n            finished.send(completion: .finished)\n            return Records(iterator: finished.makeAsyncIterator())",
        mode="stmt",
    ),
    Mutant("releasekeepsoldsubscription", S, "state.withLock { $0 = .idle(iterator) }", "", mode="stmt"),
]
