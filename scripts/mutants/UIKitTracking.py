# Planted bugs for UIKitTracking. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/UIKitTracking/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent to the original. Mutants with module="SwiftUITracking"
# plant bugs in the bridge between SwiftUI's environment and the trait, which only UIKit
# platforms compile.
#
# UIKitTrackingTests runs in the iOS simulator (SIMULATOR_TESTS in scripts/modules.py), and
# `just mutate` builds and runs SwiftPM test bundles on the Mac, where this module is empty, so
# these mutants are run one at a time against `bazel test //Tests/UIKitTrackingTests` instead.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `file:` swapped for `fileID:` in the call site: in the Swift 6 language mode `#file` is
#   `#fileID`.
# - `[weak self]` made a strong capture: the control and its action then keep each other alive,
#   a leak no test observes through what is tracked.

TESTS = ["UIKitTrackingTests"]

T = "TrackerTrait.swift"
C = "UIControl+Track.swift"
B = "EnvironmentValues+Tracker.swift"

# The call site the action tracks with.
SITE = "track(event, file: file, fileID: fileID, function: function, line: line, column: column)"

MUTANTS = [
    # The trait.
    # The first two `.noOp`s are the doc comments'.
    Mutant("defaulttracks", T, ".noOp", "Tracker()", nth=2),
    # The first is UITraitCollection's getter, the second UIMutableTraits's.
    Mutant("collectiondefault", T, "self[TrackerTrait.self]", "TrackerTrait.defaultValue", nth=0),
    Mutant("overridesdefault", T, "self[TrackerTrait.self]", "TrackerTrait.defaultValue", nth=1),
    Mutant("notset", T, "self[TrackerTrait.self] = newValue", "", mode="stmt"),
    # UIControl.track(_:for:).
    # The weak `self` still read, and the line moved rather than swapped for the column, so each
    # builds alone under Bazel's warnings as errors, where these mutants run.
    Mutant("nottracked", C, "self?.traitCollection.tracker." + SITE, "_ = self", mode="stmt"),
    Mutant("sitemoved", C, "self?.traitCollection.tracker." + SITE, "self?.traitCollection.tracker." + SITE.replace("line: line,", "line: line + 1,")),
    # The first `.primaryActionTriggered` is the doc comment's.
    Mutant("defaultevent", C, ".primaryActionTriggered", ".touchUpInside", nth=1),
    # The statement first, so the expression's mutant finds its text in the else branch.
    Mutant("notadded", C, "addAction(action, for: controlEvents)", "", mode="stmt"),
    Mutant("everyevent", C, "addAction(action, for: controlEvents)", "addAction(action, for: .allEvents)"),
    Mutant("otheraction", C, "return action", "return UIAction { _ in }", mode="stmt"),
    # The bridge, in SwiftUITracking.
    # The first `traitCollection.tracker` is the doc comment's.
    Mutant("bridgenotread", B, "traitCollection.tracker", ".noOp", nth=1, module="SwiftUITracking"),
    Mutant("bridgenotwritten", B, "mutableTraits.tracker = value", "", mode="stmt", module="SwiftUITracking"),
]
