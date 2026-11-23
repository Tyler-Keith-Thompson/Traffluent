#if canImport(UIKit) && !os(watchOS)
import Events
import Foundation
import Instrumentation
import SwiftUITracking
import Trackers
import UIKit
import UIKitTracking

/// Watches the windows of one window scene for touches that activate a UIKit control, and tracks
/// each activation through the control's own tracker.
///
/// A ``ControlTouchRecognizer`` in each window reports the control each touch begins on; this
/// becomes a target of that control, for the events an activation sends, the first time. When the
/// control sends one after a touch began on it, before the next touch begins, the activation is
/// tracked, once per touch.
// The two halves, a recognizer and a target, are the one way to learn that a touch activated a
// control using public API alone and nothing global. The recognizer finds the controls and says
// which touch is on each, and the control itself says it activated, so a touch that ends outside
// it or is cancelled tracks nothing. Rejected:
// - Swizzling `UIControl.sendAction(_:to:for:)` or `UIApplication.sendAction(_:to:from:for:)`
//   (what other analytics SDKs do): it changes every control in the process, every scene's alike,
//   and the charter rules it out (N2).
// - A `UIApplication` or `UIWindow` subclass overriding `sendEvent(_:)`: the app would have to
//   adopt it, and the application's is one per process.
// - Judging the activation from the touch alone, as ending inside the control: it can't tell a
//   control that ignored the touch (disabled, or one that tracks a drag) from one that acted.
// - The `UIEvent` a control passes its targets, checked for a touch: a control that acts from a
//   gesture recognizer of its own, as `UISwitch` does, passes none.
// - Counting an action only until the touch's end has been handled: `UISwitch` sends its
//   actions once its animation ends, turns of the run loop after the touch. So an activation counts
//   until the next touch begins instead; an action the app sends itself in between, to a control
//   the last touch was on and didn't activate, counts too.
// - Walking each window's views for controls to add a target to: work on every change to any
//   view, for controls that may never be touched.
// - Accessibility notifications: none is posted for a control's activation.
@MainActor
final class ControlDiscovery: NSObject {
    private weak var scene: UIWindowScene?
    private let controlActivated: @MainActor (DiscoveredControl) -> ControlActivated?
    private let callSite: SourceLocation
    /// The recognizer added to each watched window, held weakly with it: a window that has gone
    /// is not kept alive.
    private var recognizers: [WatchedWindow] = []
    /// The controls this is a target of, held weakly: a control that has gone is not kept alive.
    private var controls: [WeakControl] = []
    /// The controls a touch is on, or the last touch was on, until the next touch begins.
    private var touched: [TouchedControl] = []
    private var windowObserver: (any NSObjectProtocol)?

    /// Discovery of the control activations in `scene`'s windows.
    ///
    /// - Parameters:
    ///   - scene: The window scene to watch.
    ///   - controlActivated: The event for an activated control, or `nil` to skip it.
    ///   - callSite: The call site each activation records.
    init(
        scene: UIWindowScene,
        controlActivated: @escaping @MainActor (DiscoveredControl) -> ControlActivated?,
        callSite: SourceLocation
    ) {
        self.scene = scene
        self.controlActivated = controlActivated
        self.callSite = callSite
        super.init()
        watchWindows()
        // A window the scene shows later is watched as it becomes visible: any window becoming
        // visible looks again at the scene's windows, a short list. Hidden windows get no
        // touches, so a window made but never shown needs nothing yet.
        windowObserver = NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { [weak self] _ in
            // Posted on the main thread, and delivered on the main queue.
            MainActor.assumeIsolated {
                self?.watchWindows()
            }
        }
    }

    isolated deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
        for watched in recognizers {
            if let window = watched.window, let recognizer = watched.recognizer {
                window.removeGestureRecognizer(recognizer)
            }
        }
        for weakControl in controls {
            weakControl.control?.removeTarget(self, action: #selector(controlSentAction(_:)), for: Self.activationEvents)
        }
    }

    /// The control events that count as an activation: a button's tap, a switch's, slider's or
    /// segmented control's change, and a custom control's touch up.
    private static let activationEvents: UIControl.Event = [.primaryActionTriggered, .touchUpInside, .valueChanged]

    /// Adds a recognizer to each of the scene's windows that has none yet.
    private func watchWindows() {
        recognizers.removeAll { $0.window == nil }
        for window in scene?.windows ?? [] where !recognizers.contains(where: { $0.window === window }) {
            let recognizer = ControlTouchRecognizer { [weak self] touch, control in
                self?.touch(touch, began: control)
            } touchesEnded: { [weak self] touches in
                self?.touchesEnded(touches)
            }
            window.addGestureRecognizer(recognizer)
            recognizers.append(WatchedWindow(window: window, recognizer: recognizer))
        }
    }

    /// Forgets the controls touches that have ended were on; then notes that `touch` is on
    /// `control`, if it is in one, and becomes a target of the control, unless it already is, or
    /// the control is SwiftUI's.
    private func touch(_ touch: UITouch, began control: UIControl?) {
        touched.removeAll(where: \.hasEnded)
        guard let control, !control.isInSwiftUI else { return }
        touched.append(TouchedControl(control: control, touch: ObjectIdentifier(touch)))
        if !control.allTargets.contains(self) {
            controls.removeAll { $0.control == nil }
            control.addTarget(self, action: #selector(controlSentAction(_:)), for: Self.activationEvents)
            controls.append(WeakControl(control: control))
        }
    }

    /// Notes that `touches` have ended. The controls they were on are forgotten as the next touch
    /// begins, as a control may still send its actions until then.
    private func touchesEnded(_ touches: [ObjectIdentifier]) {
        for index in touched.indices where touches.contains(touched[index].touch) {
            touched[index].hasEnded = true
        }
    }

    /// Tracks the activation of `control`, if the last touch on it hasn't activated it yet and no
    /// touch has begun since it ended.
    @objc private func controlSentAction(_ control: UIControl) {
        guard let index = touched.firstIndex(where: { $0.control === control && !$0.isTracked }) else { return }
        touched[index].isTracked = true
        let discovered = DiscoveredControl(identifier: control.identifier, kind: control.kind, screen: control.screen)
        guard let activation = controlActivated(discovered) else { return }
        var context = ServiceContext.current ?? .topLevel
        context[ScreenKey.self] = discovered.screen
        // The screen goes in the context the tracker captures, before its enrichers run, so a
        // tracker enriched with a screen of its own (a view controller's) sets that one instead.
        ServiceContext.withValue(context) {
            control.traitCollection.tracker.track(activation, file: callSite.file, fileID: callSite.fileID, function: callSite.function, line: callSite.line, column: callSite.column)
        }
    }
}

extension ControlDiscovery {
    /// The key a window scene keeps its discovery under, as an associated object: the address of
    /// an object no other association uses.
    static var associationKey: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(AssociationKey.instance).toOpaque())
    }
}

/// The object whose address is ``ControlDiscovery/associationKey``: a constant, holding nothing.
private final class AssociationKey: Sendable {
    static let instance = AssociationKey()
}

/// A window and the recognizer added to it, held weakly.
private struct WatchedWindow {
    weak var window: UIWindow?
    weak var recognizer: ControlTouchRecognizer?
}

/// A control, held weakly.
private struct WeakControl {
    weak var control: UIControl?
}

/// A control a touch is on, held weakly, whether the touch has activated it yet, and whether the
/// touch has ended.
private struct TouchedControl {
    weak var control: UIControl?
    let touch: ObjectIdentifier
    var isTracked = false
    var hasEnded = false
}

extension UIControl {
    /// The control's accessibility identifier, or `nil` if it has none or an empty one.
    fileprivate var identifier: String? {
        guard let accessibilityIdentifier, !accessibilityIdentifier.isEmpty else { return nil }
        return accessibilityIdentifier
    }

    /// The name of the first public UIKit class the control is an instance of: its own class, or
    /// the class it inherits from, that UIKit declares and doesn't mark private with a leading
    /// underscore.
    fileprivate var kind: String {
        let uiKit = Bundle(for: UIControl.self)
        let kind = sequence(first: type(of: self) as AnyClass, next: { class_getSuperclass($0) })
            .lazy
            .filter { Bundle(for: $0) == uiKit }
            .map { NSStringFromClass($0) }
            .first { !$0.hasPrefix("_") }
        // UIControl is UIKit's and public, and every control is one, so the search finds one.
        return kind ?? "UIControl"
    }

    /// The type of the nearest view controller up the control's responder chain that isn't one of
    /// UIKit's own, such as a navigation controller around a navigation bar's buttons; `nil` if
    /// there is none.
    fileprivate var screen: String? {
        let uiKit = Bundle(for: UIViewController.self)
        return sequence(first: self as UIResponder, next: \.next)
            .lazy
            .compactMap { $0 as? UIViewController }
            .first { Bundle(for: type(of: $0)) != uiKit }
            .map { String(describing: type(of: $0)) }
    }

    /// Whether the control is SwiftUI's, or inside a SwiftUI view: whether its responder chain
    /// reaches one of SwiftUI's views or view controllers, such as a hosting view, before any
    /// other view controller.
    fileprivate var isInSwiftUI: Bool {
        for responder in sequence(first: self as UIResponder, next: \.next) {
            if responder.isSwiftUI {
                return true
            }
            if responder is UIViewController {
                return false
            }
        }
        return false
    }
}

extension UIResponder {
    /// Whether the responder's class is declared in SwiftUI, by the module its Swift name gives.
    fileprivate var isSwiftUI: Bool {
        let name = String(reflecting: type(of: self))
        return name.hasPrefix("SwiftUI.") || name.hasPrefix("SwiftUICore.")
    }
}
#endif
