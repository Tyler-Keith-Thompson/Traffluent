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
# - The read-back after the delivery loop ends (`_ = await redeliverWhileCaughtUp()` and its
#   cancellation check): every drop is counted in the same lock as its yield, so the loop's last
#   pass has already read every dropped batch back; it is there in case that ever changes.
# - The cancellation check before each read-back: without it a cancelled delivery reads one more
#   batch and hands it to a destination whose receive returns at once, and the check after the
#   receive still leaves it unacknowledged. Only the extra read and receive differ, and a test
#   can't cancel exactly between two read-backs.
# - Dropping enriched(by:)'s warning for an enricher that adds records: tests don't pin logs.
# - A store returning records at positions nobody asked for: ReadBack looks each batch's records
#   up by position, so the extra ones are never sent.

TESTS = ["DestinationsTests"]

C = "ConsoleDestination.swift"
D = "Deliver.swift"
U = "DestinationBuffer.swift"
B = "Batch.swift"
M = "InMemoryDestination.swift"

MUTANTS = [
    # A batch handed over after cancellation (TRAF-71).
    Mutant("batchaftercancelmarked", "Deliver.swift", "if Task.isCancelled { break }", "", mode="stmt"),

    Mutant("linewithoutname", C, '"\\(record.name) \\(record.event)"', '"\\(record.event)"'),
    Mutant("linewithoutspace", C, '"\\(record.name) \\(record.event)"', '"\\(record.name)\\(record.event)"'),
    # The default the overload without a limit passes; the first 100 is its doc comment's, and a
    # comment in the body names 100 again.
    Mutant("defaultbufferlimit", D, "100", "99", nth=1),
    Mutant("bufferlimitzeroallowed", D, "batchBufferLimit >= 1", "batchBufferLimit >= 0"),
    Mutant("bufferonemore", U, ".bufferingNewest(limit)", ".bufferingNewest(limit + 1)"),
    Mutant("firstdestinationonly", D, "for buffer in buffers { buffer.yield(delivery) }", "buffers.first?.yield(delivery)", mode="stmt"),
    Mutant("nodelivery", U, "await destination.receive(delivery.batch)", "", mode="stmt"),
    Mutant("buffersneverfinish", D, "for buffer in buffers { buffer.finish() }", "", mode="stmt"),
    # A full buffer's drop: reported with its destination, records and timestamps (TRAF-66).
    Mutant("dropnotreported", U, "reporter?.yield(report)", "", mode="stmt"),
    Mutant("dropindexfixed", U, "self.index = index", "self.index = 0", mode="stmt"),
    # The first is the stored records' count; the second is the report's.
    Mutant("droprecordcountone", U, "dropped.batch.count", "1", nth=1),
    Mutant("dropearliestislatest", D, "earliest...latest", "latest...latest"),
    # The first leaves one copy of the original, in its unmutated branch.
    Mutant("droplatestisearliest", D, "earliest...latest", "earliest...earliest"),
    Mutant("dropstorednotcounted", U, "dropped.batch.count { $0.deliveryTag != nil }", "0"),
    # A dropped batch's stored records: never acknowledged unless read back and received.
    Mutant("dropcountsasreceived", U, "state.dropped.append(dropped)", "dropped.acknowledgement.received()", mode="stmt"),
    Mutant("readbacknotnarrowed", D, "state.stores[index].positions.removeAll { !keptInStore.contains($0) }", "", mode="stmt"),
    Mutant("emptyreadbacksent", U, "!read.records.isEmpty", "true"),
    Mutant("readbackcontextlost", U, "record.context = stored.context", "", mode="stmt"),
    Mutant("readbackotherstore", U, "$0.acknowledger === store.acknowledger ? ($0.position, record) : nil", "($0.position, record)"),
    Mutant("droppeduncapped", U, "state.dropped.count > droppedLimit", "false"),
    Mutant("droppedcaplater", U, "state.dropped.count > droppedLimit", "state.dropped.count > droppedLimit + 1"),
    Mutant("droppedcapone", U, "limit <= Int.max / 10 ? limit * 10 : Int.max", "limit"),
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
    Mutant("notenriched", "Enriched.swift", "_ = enricher(&record)", "", mode="stmt"),
    Mutant("enrichedtwice", "Enriched.swift", "_ = enricher(&record)", "_ = enricher(&record); _ = enricher(&record)", mode="stmt"),
    # InMemoryDestination: what it keeps and announces.
    Mutant("notkept", M, "log.kept.withLock { $0.append(batch) }", "", mode="stmt"),
    Mutant("notannounced", M, "log.deliveries.enqueue(batch)", "", mode="stmt"),
    Mutant("recordsfirstbatch", M, "log.kept.withLock { Array($0.records) }", "log.kept.withLock { $0.batches.first ?? [] }"),
    Mutant("eventsfirstbatch", M, "log.kept.withLock { $0.records.compactMap { $0.event as? E } }", "log.kept.withLock { ($0.batches.first ?? []).compactMap { $0.event as? E } }"),
    # InMemoryDestination's capacity.
    Mutant("capacityzeroallowed", M, "capacity >= 1", "capacity >= 0"),
    Mutant("defaultcapacity", M, "1_000", "999"),
    Mutant("evictsonelate", M, "records.count > capacity", "records.count > capacity + 1"),
    Mutant("evictsonetoomany", M, "records.count - capacity", "records.count - capacity + 1"),
    Mutant("recordsnotevicted", M, "records.removeFirst(excess)", "", mode="stmt"),
    Mutant("partialbatchdroppedwhole", M, "batchSizes[0] -= excess", "_ = batchSizes.removeFirst()", mode="stmt"),
    Mutant("emptybatchkept", M, "guard !batch.isEmpty else { return }", "", mode="stmt"),
    Mutant("deliveriesbufferonemore", M, ".newest($0)", ".newest($0 + 1)"),
    Mutant("unboundedbounded", M, "Log(capacity: nil)", "Log(capacity: InMemoryDestination.defaultCapacity)"),
    Mutant("unboundeddeliveriesbounded", M, ".unbounded", ".newest(InMemoryDestination.defaultCapacity)"),
    # The deliveries left open once every copy of the destination is gone.
    Mutant("deliveriesneverend", M, "deliveries.finish()", "", mode="stmt"),
]
