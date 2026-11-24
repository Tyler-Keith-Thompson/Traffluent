// Real touches, through XCUIApplication, on the app in App/: UIKit has no public way to make a
// touch inside a test, and automatic control tracking tracks only activations a touch causes.
//
// The app shows every record its trackers publish in the label "log", one "scene control kind
// screen" entry each, joined by " | ", in order. A test that pins what isn't tracked taps an
// untracked control first and a tracked one after, and waits for the log to show the tracked one
// alone: had the first been tracked, it would come before. It runs on an iPad, where a second
// scene shows beside the first; each scene's label shows the same log. The "Sentinel" button tracks
// "1 sentinel manual -" by hand, for tests where nothing automatic should be tracked at all.
import Testing
import XCTest

@MainActor
@Suite("trackControlsAutomatically, with real touches", .serialized, .timeLimit(.minutes(5)))
struct ControlTrackingUITests {
    @Test("Tapping a UIKit button tracks one ControlActivated named from its accessibility identifier, with its kind, its screen and the call site of trackControlsAutomatically")
    func buttonTap() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 checkout-button UIButton ControlsViewController | 1 sentinel manual -"
        let expectedCallSite = "call site matches"

        app.buttons["checkout-button"].tap()
        app.buttons["Sentinel"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        let actualCallSite = app.staticTexts["callsite"].firstMatch.label
        #expect(actual == expected)
        #expect(actualCallSite == expectedCallSite)
    }

    @Test("Flipping a UIKit switch tracks one ControlActivated of kind UISwitch")
    func switchTap() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 notifications-switch UISwitch ControlsViewController | 1 sentinel manual -"

        app.switches["notifications-switch"].tap()
        app.buttons["Sentinel"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("Each tap tracks again")
    func repeatedTaps() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 checkout-button UIButton ControlsViewController | 1 checkout-button UIButton ControlsViewController"

        app.buttons["checkout-button"].tap()
        app.buttons["checkout-button"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("By default, a control without an accessibility identifier isn't tracked")
    func unidentifiedSkipped() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 checkout-button UIButton ControlsViewController"

        app.buttons["Unidentified"].tap()
        app.buttons["checkout-button"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("A touch dragged off the control before it lifts tracks nothing")
    func draggedOff() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 notifications-switch UISwitch ControlsViewController"

        let start = app.buttons["checkout-button"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
        app.switches["notifications-switch"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("Actions the app sends itself with sendActions(for:) aren't tracked, even to a control an earlier touch left without activating it")
    func programmaticActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 sentinel manual -"

        let start = app.buttons["checkout-button"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
        app.buttons["Send actions"].tap()
        app.buttons["Sentinel"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("An action the app sends one control while a touch is on another isn't tracked")
    func actionDuringAnotherTouch() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 checkout-button UIButton ControlsViewController | 1 sentinel manual -"

        app.buttons["checkout-button"].tap()
        app.buttons["Send on touch down"].tap()
        app.buttons["Sentinel"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("SwiftUI's controls, a Button and a Toggle with accessibility identifiers in a hosting controller, are never tracked")
    func swiftUINotTracked() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "every"]
        app.launch()
        let expectedButton = "SwiftUI button 1"
        let expected = "1 checkout-button UIButton ControlsViewController"

        app.buttons["swiftui-button"].tap()
        app.switches["swiftui-toggle"].switches.firstMatch.tap()
        app.buttons["checkout-button"].tap()

        // The SwiftUI button's own action ran, so the tap reached it.
        #expect(app.buttons["swiftui-button"].wait(for: \.label, toEqual: expectedButton, timeout: 10))
        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("Article example: the predicate renames a control and skips one, and a control without an identifier stays skipped")
    func articleExample() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "article"]
        app.launch()
        let expected = "1 Checkout UIButton ControlsViewController | 1 notifications-switch UISwitch ControlsViewController"

        app.buttons["debug-menu-button"].tap()
        app.buttons["Unidentified"].tap()
        app.buttons["checkout-button"].tap()
        app.switches["notifications-switch"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("The predicate can name a control without an identifier")
    func unidentifiedNamed() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "every"]
        app.launch()
        let expected = "1 unidentified-UIButton UIButton ControlsViewController"

        app.buttons["Unidentified"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("Turned on after the scene's window is shown, it watches that window")
    func enabledAfterWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default", "-order", "after"]
        app.launch()
        let expected = "1 checkout-button UIButton ControlsViewController"

        app.buttons["checkout-button"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("Turned on once the scene's window is on screen, it watches that window")
    func enabledOnScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default", "-order", "tap"]
        app.launch()
        let expected = "1 checkout-button UIButton ControlsViewController"

        app.buttons["Start tracking"].tap()
        app.buttons["checkout-button"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("A control whose nearest view controller is UIKit's own, such as a navigation bar's, has no screen")
    func noScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 bar-button UIButton -"

        app.buttons["bar-button"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("Nothing is tracked automatically until trackControlsAutomatically is called")
    func offByDefault() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "none", "-predicate", "default"]
        app.launch()
        let expected = "1 sentinel manual -"

        app.buttons["checkout-button"].tap()
        app.switches["notifications-switch"].tap()
        app.buttons["Sentinel"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("After stopTrackingControlsAutomatically, controls aren't tracked")
    func stop() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 checkout-button UIButton ControlsViewController | 1 sentinel manual -"

        app.buttons["checkout-button"].tap()
        app.buttons["Stop tracking"].tap()
        app.buttons["checkout-button"].tap()
        app.switches["notifications-switch"].tap()
        app.buttons["Sentinel"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("A window the scene shows after the call is watched too, and a tracker enriched with a screen sets the ScreenKey")
    func laterWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "1 later-window-button UIButton Later"

        app.buttons["Show window"].tap()
        app.buttons["later-window-button"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("A second scene's controls track through its own tracker")
    func secondScene() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "all", "-predicate", "default"]
        app.launch()
        let expected = "2 checkout-button UIButton ControlsViewController"

        app.buttons["Open scene"].tap()
        let second = app.windows.containing(.navigationBar, identifier: "Scene 2").firstMatch
        #expect(second.waitForExistence(timeout: 10))
        second.buttons["checkout-button"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }

    @Test("Tracking controls in one scene doesn't track them in another")
    func perScene() {
        let app = XCUIApplication()
        app.launchArguments = ["-tracking", "first", "-predicate", "default"]
        app.launch()
        let expected = "2 sentinel manual -"

        app.buttons["Open scene"].tap()
        let second = app.windows.containing(.navigationBar, identifier: "Scene 2").firstMatch
        #expect(second.waitForExistence(timeout: 10))
        second.buttons["checkout-button"].tap()
        second.buttons["Sentinel"].tap()

        let log = app.staticTexts["log"].firstMatch
        _ = log.wait(for: \.label, toEqual: expected, timeout: 10)
        let actual = log.label
        #expect(actual == expected)
    }
}
