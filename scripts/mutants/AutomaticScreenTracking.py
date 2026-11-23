# Planted bugs for AutomaticScreenTracking. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/AutomaticScreenTracking/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Every mutant must be caught; one that survives needs a test,
# or a note here saying why it is equivalent to the original.
#
# MUTANTS run with `just mutate AutomaticScreenTracking`, against the Mac's tests
# (AutomaticScreenTrackingTests): the name reading, the discovery the platforms share, AppKit's
# side.
#
# UIKIT_MUTANTS plant bugs only the iOS simulator's tests reach (AutomaticScreenTrackingUIKitTests,
# in SIMULATOR_TESTS): UIKit's side, and what only UIKit hosting shows (presentations, a
# NavigationStack's root, a destination named after its value). `just mutate` builds SwiftPM test
# bundles on the Mac, where that code is left out or unreached, so these are planted one at a time
# in the tree, as `new` in place of `old`, and caught by a failing
# `bazel test //Tests/AutomaticScreenTrackingUIKitTests`.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `file:` swapped for `fileID:` in the call site: in the Swift 6 language mode `#file` is
#   `#fileID`.
# - The transition guard in collectScreens(into:) dropped: it only matters while a transition the
#   user may cancel runs (an interactive pop); a push or pop that completes tracks the same screens
#   either way, and no test can drive a gesture.
# - CFRunLoopObserverInvalidate dropped from the deinit: the observer's handler holds discovery
#   weakly, so a stopped discovery's observer does nothing; only the observer itself leaks.
# - trackScreen(_:) not placing its marker (TrackScreen.swift, in SwiftUITracking): not a mutant
#   the schemata can build, as the view builder's two branches would differ in type. Removing the
#   `.markedAsTrackedScreen()` line by hand fails manualScreenWins on both platforms.
# - The check that a NavigationStack's root doesn't track again the hosting controller it takes
#   its name from (`previous.contains { $0.controller === host }` made `false`): it matters only
#   when SwiftUI lays the hosting controller out a turn before it adds the stack's controllers,
#   which no test can bring about on purpose. One run of navigationStackPush hit it while it was
#   written (StackView tracked twice); in the runs since, the stack's controllers came first.
# - The observer's order or run-loop modes changed: the tests' run loop turns run in the default
#   mode, and every order after layout gives the same screens there.

TESTS = ["AutomaticScreenTrackingTests"]

N = "TypeName.swift"
D = "ScreenDiscovery.swift"
V = "ViewController.swift"
W = "NSWindow+TrackScreensAutomatically.swift"
U = "UIWindowScene+TrackScreensAutomatically.swift"

ASSOCIATE = "objc_setAssociatedObject(self, ScreenDiscovery.associationKey, discovery, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)"
DISSOCIATE = "objc_setAssociatedObject(self, ScreenDiscovery.associationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)"
MARKER = "            if next is TrackedScreenMarkerView {\n                return true\n            }"

MUTANTS = [
    # Reading a name.
    Mutant("tupleresolved", N, "!isTupleOrFunction", "true"),
    Mutant("tuplemodule", N, 'isTupleOrFunction ? "" : components.first ?? ""', 'components.first ?? ""'),
    Mutant("frameworknamed", N, "Self.frameworkModules.contains(module)", "false"),
    Mutant("lazyfirst", N, "arguments.last?.screenName", "arguments.first?.screenName"),
    Mutant("conditionalnamed", N, 'baseName == "_ConditionalContent"', "false"),
    Mutant("anyviewbytype", N, '["AnyView", "AnyViewStorage", "ModifiedContent", "_ConditionalContent"]', '["AnyViewStorage", "ModifiedContent", "_ConditionalContent"]'),
    Mutant("conditionalbytype", N, '["AnyView", "AnyViewStorage", "ModifiedContent", "_ConditionalContent"]', '["AnyView", "AnyViewStorage", "ModifiedContent"]'),
    Mutant("nodescent", N, "                value = inner", "                _ = inner", mode="stmt"),
    Mutant("localnamed", N, 'last.firstRange(of: " in ")', 'last.firstRange(of: " at ")'),
    Mutant("dotsinparentheses", N, "depth == 0", "true"),
    Mutant("arrowends", N, 'name.last != "-"', "true"),
    Mutant("nodepthbound", N, "depth < 64", "depth < 63"),
    Mutant("descriptionwithmodules", N, "arguments.map(\\.description)", "arguments.map(\\.qualifiedName)"),
    # Discovery.
    Mutant("everytimeappeared", D, "screens.filter { screen in !previous.contains { $0.controller === screen } }", "screens"),
    Mutant("notremembered", D, "shown = screens.map(WeakViewController.init)", "", mode="stmt"),
    Mutant("replacedfresh", D, "shown = previous?.shown ?? []", "shown = []", mode="stmt"),
    Mutant("frameworkscreens", D, "!screen.isFrameworkController", "true"),
    Mutant("kindsignored", D, "kinds.contains(screen.screenKind)", "true"),
    Mutant("markerignored", D, "!screen.hasTrackedScreenMarker", "true"),
    Mutant("predicateignored", D, "screenViewed(DiscoveredScreen(name: screen.screenName, kind: screen.screenKind))", "Optional(ScreenViewed(screen: screen.screenName))"),
    Mutant("sitemoved", D, "callSite.line", "callSite.line + 1"),
    Mutant("containersscreens", D, "visibleChildren.isEmpty", "true"),
    Mutant("childrenskipped", D, "children.filter(\\.isOnScreen)", "[ViewController]()"),
    Mutant("kindsswapped", D, "self is HostingController ? .swiftUI : .platformViewController", "self is HostingController ? .platformViewController : .swiftUI"),
    # AppKit's side.
    Mutant("orderedoutshown", V, "view.window?.isVisible == true", "view.window != nil"),
    Mutant("markerunseen", V, MARKER, "", mode="stmt", nth=1),
    Mutant("markershallow", V, "views += next.subviews", "_ = next", mode="stmt", nth=1),
    Mutant("trackernoop", V, "view.tracker", ".noOp"),
    Mutant("notretained", W, ASSOCIATE, "_ = discovery", mode="stmt"),
    Mutant("notstopped", W, DISSOCIATE, "", mode="stmt"),
    Mutant("noroots", W, "(self?.contentViewController).map { [$0] } ?? []", "[ViewController]()"),
]

UIKIT_MUTANTS = [
    Mutant("loadedonscreen", V, "viewIfLoaded?.window != nil", "viewIfLoaded != nil"),
    Mutant("presentedtwice", V, "presentedViewController.presentingViewController === self", "true"),
    Mutant("uikitmarkerunseen", V, MARKER, "", mode="stmt", nth=0),
    Mutant("uikitmarkershallow", V, "views += next.subviews", "_ = next", mode="stmt", nth=0),
    Mutant("traitnoop", V, "traitCollection.tracker", ".noOp"),
    Mutant("presentedskipped", D, "presentedScreens", "[ViewController]()"),
    Mutant("ancestorunnamed", D, "sequence(first: self, next: \\.parent)", "sequence(first: self, next: { _ in nil })"),
    Mutant("payloadkept", N, "mirror.children.first?.label ?? String(describing: value)", "String(describing: value)"),
    Mutant("valuetypeonly", N, "mirror.displayStyle == .enum", "false"),
    Mutant("uikitnotretained", U, ASSOCIATE, "_ = discovery", mode="stmt"),
    Mutant("uikitnotstopped", U, DISSOCIATE, "", mode="stmt"),
    Mutant("hiddenwindows", U, "(self?.windows ?? []).filter { !$0.isHidden }", "(self?.windows ?? [])"),
]
