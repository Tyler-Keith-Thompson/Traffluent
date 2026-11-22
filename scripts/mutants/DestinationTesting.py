# Planted bugs for DestinationTesting; run with `just mutate DestinationTesting`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/DestinationTesting/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent to the original.
#
# Known equivalent mutants (they survive by design): none.

TESTS = ["DestinationTestingTests"]

D = "InMemoryDestination.swift"

MUTANTS = [
    Mutant("notkept", D, "log.batches.withLock { $0.append(batch) }", "", mode="stmt"),
    Mutant("notannounced", D, "log.continuation.yield(batch)", "", mode="stmt"),
    Mutant("recordsfirstbatch", D, "log.batches.withLock { $0.flatMap { $0 } }", "log.batches.withLock { $0.first ?? [] }"),
    Mutant("eventsfirstbatch", D, "log.batches.withLock { $0.flatMap { $0.compactMap { $0.event as? E } } }", "log.batches.withLock { ($0.first ?? []).compactMap { $0.event as? E } }"),
]
