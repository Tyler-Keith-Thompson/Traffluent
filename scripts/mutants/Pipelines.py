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
    Mutant("nodestinations", P, "self.destinations = destinations", "self.destinations = []", mode="stmt"),
    Mutant("strategyignored", P, "self.strategy = strategy", "self.strategy = CountBatchStrategy<EventRecord>(1)", mode="stmt"),
    Mutant("fixedtimestamp", P, "timeOrigin.addingTimeInterval(elapsed().timeInterval)", "timeOrigin"),
    Mutant("nosend", P, SEND, "", mode="stmt"),
    # Each swaps one field of the source location; the original statement stays in the innermost
    # else branch, so every one finds it.
    Mutant("filefromfileid", P, SEND, SEND.replace("file: file,", "file: fileID,"), mode="stmt"),
    Mutant("fileidfromfile", P, SEND, SEND.replace("fileID: fileID,", "fileID: file,"), mode="stmt"),
    Mutant("functionfromfile", P, SEND, SEND.replace("function: function,", "function: file,"), mode="stmt"),
    Mutant("linefromcolumn", P, SEND, SEND.replace("line: line,", "line: column,"), mode="stmt"),
    Mutant("columnfromline", P, SEND, SEND.replace("column: column)", "column: line)"), mode="stmt"),
    Mutant("nofinish", P, "subject.send(completion: .finished)", "", mode="stmt"),
    Mutant(
        "firstdestinationonly", P,
        "for destination in destinations {\n                    group.addTask { await destination.receive(batch) }\n                }",
        "for destination in destinations.prefix(1) {\n                    group.addTask { await destination.receive(batch) }\n                }",
        mode="stmt",
    ),
    # firstdestinationonly leaves two copies of this statement; the second is the original loop's.
    Mutant("nodelivery", P, "group.addTask { await destination.receive(batch) }", "", mode="stmt", nth=1),
    Mutant("noorigin", P, "timeOrigin = Date.now", "timeOrigin = Date(timeIntervalSince1970: 0)", mode="stmt"),
    Mutant("noelapsed", P, "start.duration(to: clock.now)", "Duration.zero"),
    Mutant("wholeseconds", P, "TimeInterval(attoseconds) / 1e18", "0"),
    Mutant(
        "secondrunallowed", S,
        'preconditionFailure("A pipeline runs once")',
        "let finished = PassthroughSubject<EventRecord>()\n            finished.send(completion: .finished)\n            return Records(iterator: finished.makeAsyncIterator())",
        mode="stmt",
    ),
]
