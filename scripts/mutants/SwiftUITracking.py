# Planted bugs for SwiftUITracking; run with `just mutate SwiftUITracking`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/SwiftUITracking/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent to the original. Tracker.enriched(by:), which trackScreen
# builds on, is Trackers's, and planted there.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `file:` swapped for `fileID:` in a call site: in the Swift 6 language mode `#file` is `#fileID`.
# - trackChange's event made from the modifier's stored `value` rather than the closure's
#   `newValue`: SwiftUI runs the action with the body built from the new value, so the two agree.
# - A modifier's tracker read in its closure rather than captured in the body: the closure runs
#   while the modifier is installed, so both read the same environment.

TESTS = ["SwiftUITrackingTests"]

E = "EnvironmentValues+Tracker.swift"
C = "CallSite.swift"
A = "TrackOnAppear.swift"
P = "TrackOnTap.swift"
H = "TrackChange.swift"
S = "TrackScreen.swift"
V = "ScreenViewed.swift"

# The call site CallSite.track forwards, swapped whole, one field at a time.
FORWARD = "track(event, file: callSite.file, fileID: callSite.fileID, function: callSite.function, line: callSite.line, column: callSite.column)"
# ScreenViewed's one property in its schema.
PROPERTY = 'EventSchema.Property(name: "screen", typeName: "String", isOptional: false)'
# The call site each modifier builds from its defaults.
SITE = "CallSite(file: file, fileID: fileID, function: function, line: line, column: column)"

MUTANTS = [
    # The environment.
    # The first `.noOp` is the doc comment's.
    Mutant("defaulttracks", E, ".noOp", "Tracker()", nth=1),
    Mutant("trackernotset", E, "environment(\\.tracker, tracker)", "environment(\\.tracker, .noOp)"),
    # The call site.
    Mutant("forwardline", C, FORWARD, FORWARD.replace("line: callSite.line", "line: callSite.column")),
    Mutant("forwardcolumn", C, FORWARD, FORWARD.replace("column: callSite.column", "column: callSite.line")),
    Mutant("forwardfunction", C, FORWARD, FORWARD.replace("function: callSite.function", "function: callSite.fileID")),
    Mutant("forwardfileid", C, FORWARD, FORWARD.replace("fileID: callSite.fileID", "fileID: callSite.function")),
    Mutant("appearsite", A, SITE, SITE.replace("line: line,", "line: column,")),
    Mutant("tapsite", P, SITE, SITE.replace("line: line,", "line: column,")),
    Mutant("changesite", H, SITE, SITE.replace("line: line,", "line: column,")),
    Mutant("screensite", S, SITE, SITE.replace("line: line,", "line: column,")),
    # trackOnAppear.
    Mutant("appearnottracked", A, "tracker.track(event, from: callSite)", "", mode="stmt"),
    Mutant("appeartrackedtwice", A, "tracker.track(event, from: callSite)", "tracker.track(event, from: callSite)\ntracker.track(event, from: callSite)", mode="stmt"),
    # trackOnTap.
    Mutant("tapnottracked", P, "tracker.track(event, from: callSite)", "", mode="stmt"),
    Mutant("taptrackedtwice", P, "tracker.track(event, from: callSite)", "tracker.track(event, from: callSite)\ntracker.track(event, from: callSite)", mode="stmt"),
    # trackChange.
    Mutant("changenottracked", H, "tracker.track(event(newValue), from: callSite)", "", mode="stmt"),
    Mutant("changeinitial", H, "false", "true"),
    # trackScreen.
    Mutant("screenkeynotset", S, "context[ScreenKey.self] = screen", "", mode="stmt"),
    Mutant("screenkeyempty", S, "context[ScreenKey.self] = screen", 'context[ScreenKey.self] = ""', mode="stmt"),
    # The statement first, then the expressions inside it, so each finds its text in the else branch.
    Mutant("viewednottracked", S, "screenTracker.track(ScreenViewed(screen: screen), from: callSite)", "", mode="stmt"),
    Mutant("viewedunnamed", S, "ScreenViewed(screen: screen)", 'ScreenViewed(screen: "")'),
    # The second `screenTracker` is the environment's, the third the one ScreenViewed is tracked through.
    Mutant("screennotinenvironment", S, "screenTracker", "tracker", nth=1),
    Mutant("viewedwithoutscreen", S, "screenTracker", "tracker", nth=2),
    # ScreenViewed.
    Mutant("screennotencoded", V, "encoder.encode(screen)", "", mode="stmt"),
    # The second `1` is the schema's version; the first, its doc comment's.
    Mutant("schemaversion", V, "1", "0", nth=1),
    # The whole list first, so the property's own mutants find it in the else branch.
    Mutant("schemanoproperty", V, "[" + PROPERTY + "]", "[]"),
    Mutant("schemaoptional", V, PROPERTY, PROPERTY.replace("isOptional: false", "isOptional: true")),
    Mutant("schematype", V, PROPERTY, PROPERTY.replace('typeName: "String"', 'typeName: "Int"')),
    Mutant("schemaname", V, PROPERTY, PROPERTY.replace('name: "screen"', 'name: "name"')),
]
