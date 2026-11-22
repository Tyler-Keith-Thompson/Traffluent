# Planted bugs for Trackers; run with `just mutate Trackers`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Trackers/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (they survive by design): none.

TESTS = ["TrackersTests"]

T = "Tracker.swift"
W = "WithTracker.swift"

MUTANTS = [
    Mutant("currentignoresbinding", T, "bound ?? .noOp", ".noOp"),
    Mutant("pipelinedropped", T, "pipeline.track(event, file: file, fileID: fileID, function: function, line: line, column: column)", "", mode="stmt"),
    Mutant("ownline", T, "pipeline.track(event, file: file, fileID: fileID, function: function, line: line, column: column)", "pipeline.track(event, file: file, fileID: fileID, function: function, line: #line, column: column)", mode="stmt"),
    Mutant("ownfunction", T, "pipeline.track(event, file: file, fileID: fileID, function: function, line: line, column: column)", "pipeline.track(event, file: file, fileID: fileID, function: #function, line: line, column: column)", mode="stmt"),
    Mutant("syncunbound", W, "return try Tracker.$bound.withValue(tracker, operation: operation)", "return try operation()", mode="stmt"),
    Mutant("asyncunbound", W, "return try await Tracker.$bound.withValue(tracker, operation: operation)", "return try await operation()", mode="stmt"),
]
