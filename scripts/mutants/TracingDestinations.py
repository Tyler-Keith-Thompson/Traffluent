# Planted bugs for TracingDestinations; run with `just mutate TracingDestinations`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/TracingDestinations/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent to the original.
#
# Known equivalent mutants (they survive by design): none.

TESTS = ["TracingDestinationsTests"]

S = "SpanEventDestination.swift"

MUTANTS = [
    Mutant("deliverytimespan", S, "tracer.activeSpan(identifiedBy: record.context)?.addEvent(record.spanEvent)", "tracer.activeSpan(identifiedBy: ServiceContext.current ?? .topLevel)?.addEvent(record.spanEvent)", mode="stmt"),
    Mutant("noevent", S, "tracer.activeSpan(identifiedBy: record.context)?.addEvent(record.spanEvent)", "", mode="stmt"),
    Mutant("nodescription", S, 'attributes["event"] = String(describing: event)', "", mode="stmt"),
    Mutant("filepathfromfunction", S, 'attributes["code.filepath"] = sourceLocation.fileID', 'attributes["code.filepath"] = sourceLocation.function', mode="stmt"),
    Mutant("nofunction", S, 'attributes["code.function"] = sourceLocation.function', "", mode="stmt"),
    Mutant("linefromcolumn", S, 'attributes["code.lineno"] = Int64(sourceLocation.line)', 'attributes["code.lineno"] = Int64(sourceLocation.column)', mode="stmt"),
    Mutant("columnfromline", S, 'attributes["code.column"] = Int64(sourceLocation.column)', 'attributes["code.column"] = Int64(sourceLocation.line)', mode="stmt"),
    Mutant("deliverytime", S, "return SpanEvent(name: name, at: instant, attributes: attributes)", "return SpanEvent(name: name, at: DefaultTracerClock.now, attributes: attributes)", mode="stmt"),
    Mutant("noclamplow", S, "return UInt64(min(max(seconds, 0), 18_446_744_073) * 1_000_000_000)", "return UInt64(max(min(seconds, 18_446_744_073), 0.5) * 1_000_000_000)", mode="stmt"),
    Mutant("namefixed", S, "return SpanEvent(name: name, at: instant, attributes: attributes)", 'return SpanEvent(name: "event", at: instant, attributes: attributes)', mode="stmt"),
]
