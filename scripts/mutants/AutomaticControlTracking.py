# Planted bugs for AutomaticControlTracking. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/AutomaticControlTracking/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a test,
# or a note here saying why it is equivalent to the original.
#
# MUTANTS run with `just mutate AutomaticControlTracking`, against the tests every platform runs
# (AutomaticControlTrackingTests): the event, ControlActivated.
#
# UIKIT_MUTANTS plant bugs in the tracking itself, which only real touches reach: the UI tests in
# Tests/AutomaticControlTrackingUITests (a hand-written ios_ui_test, outside SwiftPM). `just mutate`
# builds SwiftPM test bundles on the Mac, where that code is left out, so these are planted one at
# a time in the tree, as `new` in place of `old`, and caught by a failing
# `bazel test //Tests/AutomaticControlTrackingUITests`.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `file:` swapped for `fileID:` in the call site: in the Swift 6 language mode `#file` is
#   `#fileID`.
# - The check that a window has no recognizer yet (`!recognizers.contains { $0.window === window }`
#   made `true`): a window watched twice has two recognizers, which report the same control, and the
#   second report finds the target already added.
# - The check that the control doesn't have the target yet (`!control.allTargets.contains(self)`
#   made `true`): UIKit adds a target-action pair a control already has only once.
# - The leading-underscore check in `kind` dropped: the app can make no control of a private UIKit
#   class, and the ones UIKit makes (a navigation bar's back button) have no identifier.
# - The stop at the first view controller in `isInSwiftUI` dropped: above an app's view controller,
#   the responder chain holds a window, the scene, the application and its delegate, none SwiftUI's,
#   unless the window's root is a hosting controller, whose own view then comes first.
# - The recognizer's `state = .failed` once its touches end dropped: UIKit fails a recognizer still
#   possible when its touches end, and resets it.
# - The recognizer's report from `reset()` dropped: it matters only when another recognizer takes
#   the touches over (a scroll view's pan), which then cancels them in the control, so the control
#   sends no activation for the touch the stale entry names.
# - Watching the scene's windows as discovery starts (the first `watchWindows()` in `init`)
#   dropped: on the iOS 26.2 simulator, some window becomes visible before the first touch even when
#   tracking starts long after the scene's window is on screen (enabledOnScreen), and its
#   notification watches every window of the scene. The call stays for a scene where none does.
# - Clearing the dead entries of `recognizers` and `controls`: bookkeeping, with no effect but on
#   memory.

TESTS = ["AutomaticControlTrackingTests"]

E = "ControlActivated.swift"
D = "ControlDiscovery.swift"
R = "ControlTouchRecognizer.swift"
U = "UIWindowScene+TrackControlsAutomatically.swift"

ASSOCIATE = "objc_setAssociatedObject(self, ControlDiscovery.associationKey, discovery, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)"
DISSOCIATE = "objc_setAssociatedObject(self, ControlDiscovery.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)"

MUTANTS = [
    Mutant("kindkeyedascontrol", E, 'map.encode(kind, forKey: "kind")', 'map.encode(kind, forKey: "control")', mode="stmt"),
    Mutant("kindunread", E, '        kind = try map.decode(forKey: "kind")', "        kind = control", mode="stmt"),
    Mutant("schemaversion", E, "schemaVersion", "2"),
    Mutant("schemaoptional", E, 'EventSchema.Property(name: "kind", typeName: "String", isOptional: false)', 'EventSchema.Property(name: "kind", typeName: "String", isOptional: true)'),
]

UIKIT_MUTANTS = [
    Mutant("notretained", U, ASSOCIATE, "_ = discovery", mode="stmt"),
    Mutant("notstopped", U, DISSOCIATE, "", mode="stmt"),
    Mutant("identifierignored", U, "control.identifier.map { ControlActivated(control: $0, kind: control.kind) }", 'ControlActivated(control: control.identifier ?? "", kind: control.kind)'),
    Mutant("sitemoved", D, "line: callSite.line", "line: callSite.line + 1"),
    Mutant("laterwindowsunwatched", D, "                self?.watchWindows()", "                _ = self", mode="stmt"),
    Mutant("otherscenewindows", D, "scene?.windows ?? []", "(UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\\.windows))"),
    Mutant("swiftuitracked", D, "!control.isInSwiftUI", "true"),
    Mutant("anyaction", D, "$0.control === control && !$0.isTracked", "!$0.isTracked"),
    Mutant("everyaction", D, "$0.control === control && !$0.isTracked", "$0.control === control"),
    Mutant("notremembered", D, "        touched[index].isTracked = true", "", mode="stmt"),
    Mutant("neverforgotten", D, "        touched.removeAll(where: \\.hasEnded)", "", mode="stmt"),
    Mutant("forgottenatend", D, "            touched[index].hasEnded = true", "            touched.remove(at: index)\n            break", mode="stmt"),
    Mutant("endsunreported", R, "        touchesEnded(identities)", "        _ = identities", mode="stmt"),
    Mutant("predicateignored", D, "controlActivated(discovered)", 'Optional(ControlActivated(control: discovered.identifier ?? "", kind: discovered.kind))'),
    Mutant("noscreen", D, "context[ScreenKey.self] = discovered.screen", "context[ScreenKey.self] = nil"),
    Mutant("scenetracker", D, "control.traitCollection.tracker", "(scene?.traitCollection.tracker ?? .noOp)"),
    Mutant("emptyidentifier", D, "!accessibilityIdentifier.isEmpty", "true"),
    Mutant("appkind", D, ".filter { Bundle(for: $0) == uiKit }", ".filter { _ in _ = uiKit; return true }"),
    Mutant("uikitscreen", D, ".first { Bundle(for: type(of: $0)) != uiKit }", ".first { _ in _ = uiKit; return true }"),
    Mutant("controlonly", R, "sequence(first: self, next: \\.superview)", "sequence(first: self, next: { _ in nil })"),
    Mutant("notdiscovered", R, "touchBegan(touch, touch.view?.enclosingControl)", "touchBegan(touch, nil)"),
]
