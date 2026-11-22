# Planted bugs for Destinations; run with `just mutate Destinations`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Destinations/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Dropping `print(line(for: record))` from ConsoleDestination.receive: what it writes to standard
#   output is the observable effect, and tests don't capture the process's output.

TESTS = ["DestinationsTests"]

C = "ConsoleDestination.swift"

MUTANTS = [
    Mutant("linewithoutname", C, '"\\(record.name) \\(record.event)"', '"\\(record.event)"'),
    Mutant("linewithoutspace", C, '"\\(record.name) \\(record.event)"', '"\\(record.name)\\(record.event)"'),
]
