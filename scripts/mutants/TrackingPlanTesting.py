# Planted bugs for TrackingPlanTesting; run with `just mutate TrackingPlanTesting`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/TrackingPlanTesting/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a
# test, or a note here saying why it is equivalent to the original.
#
# Known equivalent mutants (they survive by design): none.

TESTS = ["TrackingPlanTestingTests"]

E = "ExpectTrackingPlan.swift"

MUTANTS = [
    Mutant("neverrecords", E, "check != .matches", "false"),
    Mutant("alwaysrecords", E, "check != .matches", "true"),
    # callerlocationlost comes first; its replacement repeats the comment, so nodirectory picks the
    # original's, the second.
    Mutant("callerlocationlost", E, 'Issue.record(Comment(rawValue: "\\(directory.path): \\(check)"), sourceLocation: sourceLocation)', 'Issue.record(Comment(rawValue: "\\(directory.path): \\(check)"))', mode="stmt"),
    Mutant("nodirectory", E, '"\\(directory.path): \\(check)"', '"\\(check)"', nth=1),
    Mutant("returnsmatch", E, "return check", "return .matches", mode="stmt"),
]
