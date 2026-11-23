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
M = "InMemoryDestination.swift"

MUTANTS = [
    Mutant("linewithoutname", C, '"\\(record.name) \\(record.event)"', '"\\(record.event)"'),
    Mutant("linewithoutspace", C, '"\\(record.name) \\(record.event)"', '"\\(record.name)\\(record.event)"'),
    # The parameter's default; a comment in the body names 100 again.
    Mutant("defaultbufferlimit", D, "100", "99", nth=0),
    Mutant("bufferlimitzeroallowed", D, "batchBufferLimit >= 1", "batchBufferLimit >= 0"),
    Mutant("bufferonemore", D, ".bufferingNewest(batchBufferLimit)", ".bufferingNewest(batchBufferLimit + 1)"),
    Mutant("firstdestinationonly", D, "for buffer in buffers { buffer.yield(delivery) }", "buffers.first?.yield(delivery)", mode="stmt"),
    Mutant("nodelivery", D, "await destination.receive(delivery.batch)", "", mode="stmt"),
    Mutant("buffersneverfinish", D, "for buffer in buffers { buffer.finish() }", "", mode="stmt"),
    # The doc comment spells the default strategy out first, so the code's copy is the second.
    Mutant("defaulttimeonotherclock", B, ".time(interval: .seconds(30), clock: clock)", ".time(interval: .seconds(30), clock: ContinuousClock())", nth=1),
    Mutant("defaultcount", B, ".count(20)", ".count(19)", nth=1),
    # After the doc comment's, defaulttimeonotherclock leaves two copies; the second is the original's.
    Mutant("defaultinterval", B, ".seconds(30)", ".seconds(31)", nth=2),
    # The destination modifiers.
    Mutant("acceptseverything", "Accepting.swift", "accepted.contains(record.consentCategory) ? record : nil", "record"),
    Mutant("acceptsothers", "Accepting.swift", "accepted.contains(record.consentCategory) ? record : nil", "accepted.contains(record.consentCategory) ? nil : record"),
    Mutant("emptytransformedsent", "TransformingDestination.swift", "guard !transformed.isEmpty else { return }", "", mode="stmt"),
    Mutant("untransformedsent", "TransformingDestination.swift", "await base.receive(transformed)", "await base.receive(batch)", mode="stmt"),
    Mutant("callsitekept", "DroppingCallSite.swift", "record.sourceLocation = nil", "", mode="stmt"),
    Mutant("notredacted", "RedactingSensitiveValues.swift", "record.revealsSensitiveValues = false", "", mode="stmt"),
    # InMemoryDestination: what it keeps and announces.
    Mutant("notkept", M, "log.kept.withLock { $0.append(batch) }", "", mode="stmt"),
    Mutant("notannounced", M, "log.continuation.yield(batch)", "", mode="stmt"),
    Mutant("recordsfirstbatch", M, "log.kept.withLock { Array($0.records) }", "log.kept.withLock { $0.batches.first ?? [] }"),
    Mutant("eventsfirstbatch", M, "log.kept.withLock { $0.records.compactMap { $0.event as? E } }", "log.kept.withLock { ($0.batches.first ?? []).compactMap { $0.event as? E } }"),
    # InMemoryDestination's capacity.
    Mutant("capacityzeroallowed", M, "capacity >= 1", "capacity >= 0"),
    Mutant("checkedcapacityzeroallowed", M, "checkedCapacity >= 1", "checkedCapacity >= 0"),
    Mutant("defaultcapacity", M, "1_000", "999"),
    Mutant("evictsonelate", M, "records.count > capacity", "records.count > capacity + 1"),
    Mutant("evictsonetoomany", M, "records.count - capacity", "records.count - capacity + 1"),
    Mutant("recordsnotevicted", M, "records.removeFirst(excess)", "", mode="stmt"),
    Mutant("partialbatchdroppedwhole", M, "batchSizes[0] -= excess", "_ = batchSizes.removeFirst()", mode="stmt"),
    Mutant("emptybatchkept", M, "guard !batch.isEmpty else { return }", "", mode="stmt"),
    Mutant("deliveriesbufferonemore", M, ".bufferingNewest(capacity)", ".bufferingNewest(capacity + 1)"),
    Mutant("unboundedbounded", M, "Log(capacity: nil)", "Log(capacity: InMemoryDestination.defaultCapacity)"),
    Mutant("unboundeddeliveriesbounded", M, ".unbounded", ".bufferingNewest(InMemoryDestination.defaultCapacity)"),
]
