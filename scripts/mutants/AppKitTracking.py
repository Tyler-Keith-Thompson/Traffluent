# Planted bugs for AppKitTracking; run with `just mutate AppKitTracking`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/AppKitTracking/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `file:` swapped for `fileID:` in the call site: in the Swift 6 language mode `#file` is
#   `#fileID`.
# - The association policy made OBJC_ASSOCIATION_RETAIN (atomic): the control is only touched on
#   the main actor.

TESTS = ["AppKitTrackingTests"]

V = "NSView+Tracker.swift"
C = "NSControl+Track.swift"

# The call site the tracking action tracks with.
SITE = "track(event, file: file, fileID: fileID, function: function, line: line, column: column)"
# The lookup's whole order: the responder chain, the window's delegate, the application's delegate.
CHAIN = "sequence(first: self as NSResponder, next: \\.nextResponder)\n            .lazy\n            .compactMap { $0 as? TrackerProviding }\n            .first"
WINDOW = "window?.delegate as? TrackerProviding"
APPLICATION = "NSApp?.delegate as? TrackerProviding"
RETURN = "\n        return provider?.tracker ?? .noOp"
LOOKUP = f"let provider = {CHAIN}\n            ?? {WINDOW}\n            ?? {APPLICATION}{RETURN}"
# The tracking action's body: track, then send the control's own action.
SEND = "        track(sender)\n        if let action {\n            sender.sendAction(action, to: target)\n        }"

MUTANTS = [
    # NSView.tracker. The orders first, with the return that reads the provider each declares; the
    # pieces' own mutants then pick their text's third occurrence, in the original's else branch.
    Mutant("delegatebeforechain", V, "        " + LOOKUP, f"        let provider = {WINDOW}\n            ?? {CHAIN}\n            ?? {APPLICATION}{RETURN}", mode="stmt"),
    Mutant("applicationbeforewindow", V, "        " + LOOKUP, f"        let provider = {CHAIN}\n            ?? {APPLICATION}\n            ?? {WINDOW}{RETURN}", mode="stmt"),
    Mutant("viewonly", V, "sequence(first: self as NSResponder, next: \\.nextResponder)", "sequence(first: self as NSResponder, next: { _ in nil })", nth=2),
    Mutant("nowindowdelegate", V, WINDOW, "nil as (any TrackerProviding)?", nth=2),
    Mutant("noapplicationdelegate", V, APPLICATION, "nil as (any TrackerProviding)?", nth=2),
    Mutant("defaulttracks", V, "provider?.tracker ?? .noOp", "provider?.tracker ?? Tracker()", nth=2),
    # NSControl.track(_:).
    Mutant("nottracked", C, "control.tracker." + SITE, "", mode="stmt"),
    Mutant("sitecolumn", C, "control.tracker." + SITE, "control.tracker." + SITE.replace("line: line,", "line: column,")),
    Mutant("notretained", C, "objc_setAssociatedObject(self, Unmanaged.passUnretained(tracking).toOpaque(), tracking, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)", "", mode="stmt"),
    Mutant("sharedkey", C, "Unmanaged.passUnretained(tracking).toOpaque()", "UnsafeMutableRawPointer(bitPattern: 1)!"),
    Mutant("targetkept", C, "target = tracking", "", mode="stmt"),
    # The body first, so the statements' own mutants find their text in the else branch.
    Mutant("tracksafteraction", C, SEND, "        if let action {\n            sender.sendAction(action, to: target)\n        }\n        track(sender)", mode="stmt"),
    # The second `sendAction` is the original's, in the else branch.
    Mutant("actionnotsent", C, "sender.sendAction(action, to: target)", "", mode="stmt", nth=1),
    Mutant("targetlost", C, "sender.sendAction(action, to: target)", "sender.sendAction(action, to: nil)", nth=1),
]
