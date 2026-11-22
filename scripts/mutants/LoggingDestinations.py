# Planted bugs for LoggingDestinations; run with `just mutate LoggingDestinations`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/LoggingDestinations/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent to the original.
#
# Known equivalent mutants (they survive by design): none. Writing the context after the fixed
# keys is pinned by "A context value named like a fixed key doesn't replace the event", but has no
# mutant: moving a statement isn't something the stmt mode can express in one line.

TESTS = ["LoggingDestinationsTests"]

L = "LoggerDestination.swift"

MUTANTS = [
    Mutant("defaultlevel", L, ".info", "Logger.Level.notice"),
    Mutant("levelignored", L, "self.level = level", "self.level = .info", mode="stmt"),
    Mutant("nolog", L, "batch.forEach(write)", "", mode="stmt"),
    Mutant("firstonly", L, "batch.forEach(write)", "batch.prefix(1).forEach(write)", mode="stmt"),
        Mutant("nocontext", L, "metadata[key.name] = .string(String(describing: value))", "", mode="stmt"),
    Mutant("noevent", L, 'metadata["event"] = .string(String(describing: event))', "", mode="stmt"),
    Mutant("notimestamp", L, 'metadata["event.timestamp"] = .string(timestamp.formatted(.iso8601))', "", mode="stmt"),
    Mutant("filepathfromfunction", L, 'metadata["code.filepath"] = .string(sourceLocation.fileID)', 'metadata["code.filepath"] = .string(sourceLocation.function)', mode="stmt"),
    Mutant("nofunction", L, 'metadata["code.function"] = .string(sourceLocation.function)', "", mode="stmt"),
    Mutant("linefromcolumn", L, 'metadata["code.lineno"] = .string(String(sourceLocation.line))', 'metadata["code.lineno"] = .string(String(sourceLocation.column))', mode="stmt"),
    Mutant("columnfromline", L, 'metadata["code.column"] = .string(String(sourceLocation.column))', 'metadata["code.column"] = .string(String(sourceLocation.line))', mode="stmt"),
]
