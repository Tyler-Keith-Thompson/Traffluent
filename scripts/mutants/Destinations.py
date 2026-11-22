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
# - The default clock (ContinuousClock) swapped for SuspendingClock in `batch(clock:)`: the two
#   differ only while the device sleeps, which no test can arrange.
# - Delivering to no destination at all: the same observable bug as nodelivery below, which
#   drops every destination's receive.

TESTS = ["DestinationsTests"]

C = "ConsoleDestination.swift"
D = "Deliver.swift"
B = "Batch.swift"

MUTANTS = [
    Mutant("linewithoutname", C, '"\\(record.name) \\(record.event)"', '"\\(record.event)"'),
    Mutant("linewithoutspace", C, '"\\(record.name) \\(record.event)"', '"\\(record.name)\\(record.event)"'),
    # The parameter's default; a comment in the body names 100 again.
    Mutant("defaultbufferlimit", D, "100", "99", nth=0),
    Mutant("bufferlimitzeroallowed", D, "batchBufferLimit >= 1", "batchBufferLimit >= 0"),
    Mutant("bufferonemore", D, ".bufferingNewest(batchBufferLimit)", ".bufferingNewest(batchBufferLimit + 1)"),
    Mutant("firstdestinationonly", D, "for buffer in buffers { buffer.yield(batch) }", "buffers.first?.yield(batch)", mode="stmt"),
    Mutant("nodelivery", D, "await destination.receive(batch)", "", mode="stmt"),
    Mutant("buffersneverfinish", D, "for buffer in buffers { buffer.finish() }", "", mode="stmt"),
    # The doc comment spells the default strategy out first, so the code's copy is the second.
    Mutant("defaulttimeonotherclock", B, ".time(interval: .seconds(30), clock: clock)", ".time(interval: .seconds(30), clock: ContinuousClock())", nth=1),
    Mutant("defaultcount", B, ".count(20)", ".count(19)", nth=1),
    # After the doc comment's, defaulttimeonotherclock leaves two copies; the second is the original's.
    Mutant("defaultinterval", B, ".seconds(30)", ".seconds(31)", nth=2),
]
