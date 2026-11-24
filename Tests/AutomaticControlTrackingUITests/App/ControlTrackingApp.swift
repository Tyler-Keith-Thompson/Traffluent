// The app the UI tests drive with real touches (XCUIApplication): a UIKit screen of controls, and
// a SwiftUI one hosted beside them, in scenes that each track through a tracker of their own. It
// shows every record its scenes' trackers publish in the label "log", which the tests read.
//
// Launch arguments set it up: `-tracking all` (every scene tracks controls automatically, the
// default), `first` (only the first scene) or `none`; `-predicate default` (the default predicate),
// `article` (the Automatic Tracking article's example, which skips "debug-menu-button" and renames
// "checkout-button") or `every` (names a control without an identifier after its kind).
import AutomaticControlTracking
import SwiftUI
import SwiftUITracking
import Trackers
import UIKit
import UIKitTracking

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// What every scene has tracked, in order, as "scene control kind screen" lines.
@MainActor
enum Log {
    static var lines: [String] = [] {
        didSet {
            for label in labels.allObjects {
                label.text = text
            }
        }
    }

    /// The lines as the label shows them; "(none)" before the first, so that the label, which an
    /// empty one isn't, is an accessibility element the tests can find.
    static var text: String {
        lines.isEmpty ? "(none)" : lines.joined(separator: " | ")
    }

    static let labels = NSHashTable<UILabel>.weakObjects()

    /// The line the default predicate's `trackControlsAutomatically()` is called on.
    static var callSiteLine = 0

    /// Whether the last automatic record's call site is where `trackControlsAutomatically()` was
    /// called, shown in the label "callsite".
    static var callSite = "(none)" {
        didSet {
            callSiteLabel?.text = callSite
        }
    }

    static weak var callSiteLabel: UILabel?

    /// What "Start tracking" runs: turning tracking on, under `-order tap`.
    static var startTracking: () -> Void = {}
    static var scenes = 0
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var records: Task<Void, Never>?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Log.scenes += 1
        let number = Log.scenes
        let tracker = Tracker()
        records = Task { @MainActor in
            for await record in tracker.records {
                guard let activation = record.event as? ControlActivated else { continue }
                // Each scene numbers its own records, so a record names the tracker it went through.
                Log.lines.append("\(number) \(activation.control) \(activation.kind) \(record.context[ScreenKey.self] ?? "-")")
                if activation.kind != "manual" {
                    let site = record.sourceLocation
                    Log.callSite = site?.fileID == #fileID && site?.line == Log.callSiteLine ? "call site matches" : "call site \(site?.fileID ?? "-"):\(site?.line ?? 0)"
                }
            }
        }
        windowScene.traitOverrides.tracker = tracker

        // `-order after` turns tracking on once the window is shown, rather than before, and
        // `-order tap` only when "Start tracking" is tapped, once the window is on screen.
        let arguments = UserDefaults.standard
        let tracking = arguments.string(forKey: "tracking") ?? "all"
        let enable = {
            if tracking == "all" || (tracking == "first" && number == 1) {
                switch arguments.string(forKey: "predicate") {
                case "article":
                    // The Automatic Tracking article's control activations example, verbatim from here.
                    windowScene.trackControlsAutomatically { control in
                        switch control.identifier {
                        case "debug-menu-button": nil  // not tracked
                        case "checkout-button": ControlActivated(control: "Checkout", kind: control.kind)
                        case let identifier?: ControlActivated(control: identifier, kind: control.kind)
                        case nil: nil  // no identifier: not tracked
                        }
                    }
                case "every":
                    windowScene.trackControlsAutomatically { control in
                        ControlActivated(control: control.identifier ?? "unidentified-\(control.kind)", kind: control.kind)
                    }
                default:
                    Log.callSiteLine = #line + 1
                    windowScene.trackControlsAutomatically()
                }
            }
        }
        if arguments.string(forKey: "order") == "tap" {
            Log.startTracking = enable
        } else if arguments.string(forKey: "order") != "after" {
            enable()
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: ControlsViewController(scene: number))
        window.makeKeyAndVisible()
        self.window = window
        if arguments.string(forKey: "order") == "after" {
            enable()
        }
    }
}

/// The SwiftUI controls, each with an accessibility identifier, which aren't tracked.
struct SwiftUIControls: View {
    @State private var isOn = false
    @State private var taps = 0

    var body: some View {
        VStack {
            Button("SwiftUI button \(taps)") { taps += 1 }
                .accessibilityIdentifier("swiftui-button")
            Toggle("SwiftUI toggle", isOn: $isOn)
                .accessibilityIdentifier("swiftui-toggle")
        }
    }
}

final class ControlsViewController: UIViewController {
    private let scene: Int
    private var laterWindow: UIWindow?
    private lazy var checkout: UIButton = {
        let button = CheckoutButton(configuration: .filled(), primaryAction: UIAction(title: "Checkout") { _ in })
        button.accessibilityIdentifier = "checkout-button"
        return button
    }()

    init(scene: Int) {
        self.scene = scene
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Scene \(scene)"
        // A control in a navigation bar, whose nearest view controller is UIKit's own.
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: button("Bar", identifier: "bar-button"))

        let log = UILabel()
        log.accessibilityIdentifier = "log"
        log.numberOfLines = 0
        log.font = .systemFont(ofSize: 10)
        log.text = Log.text
        Log.labels.add(log)

        let callSite = UILabel()
        callSite.accessibilityIdentifier = "callsite"
        callSite.font = .systemFont(ofSize: 10)
        callSite.text = Log.callSite
        Log.callSiteLabel = callSite

        let unidentified = UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Unidentified") { _ in })
        let swiftUI = UIHostingController(rootView: SwiftUIControls())
        addChild(swiftUI)

        let stack = UIStackView(arrangedSubviews: [
            checkout,
            unidentified,
            {
                let toggle = UISwitch()
                toggle.accessibilityIdentifier = "notifications-switch"
                return toggle
            }(),
            sentinel(),
            UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Send actions") { [weak self] _ in
                self?.checkout.sendActions(for: [.primaryActionTriggered, .touchUpInside])
            }),
            {
                // Sends the checkout button's actions as a touch comes down on it, while the
                // touch lasts.
                let button = UIButton(configuration: .bordered(), primaryAction: nil)
                button.setTitle("Send on touch down", for: .normal)
                button.addAction(UIAction { [weak self] _ in
                    self?.checkout.sendActions(for: [.primaryActionTriggered, .touchUpInside])
                }, for: .touchDown)
                return button
            }(),
            button("Debug menu", identifier: "debug-menu-button"),
            swiftUI.view,
            UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Open scene") { _ in
                UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest(role: .windowApplication))
            }),
            UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Show window") { [weak self] _ in
                self?.showLaterWindow()
            }),
            UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Start tracking") { _ in
                Log.startTracking()
            }),
            UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Stop tracking") { [weak self] _ in
                self?.view.window?.windowScene?.stopTrackingControlsAutomatically()
            }),
            log,
            callSite,
        ])
        swiftUI.didMove(toParent: self)
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    private func button(_ title: String, identifier: String) -> UIButton {
        let button = UIButton(configuration: .filled(), primaryAction: UIAction(title: title) { _ in })
        button.accessibilityIdentifier = identifier
        return button
    }

    /// A button without an identifier that tracks `ControlActivated(control: "sentinel", kind:
    /// "manual")` by hand: a record that comes after any automatic one a test expects not to see.
    private func sentinel() -> UIButton {
        let button = UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Sentinel") { _ in })
        button.track(ControlActivated(control: "sentinel", kind: "manual"))
        return button
    }

    /// A second window in this scene, shown after tracking started, holding one button.
    private func showLaterWindow() {
        guard let windowScene = view.window?.windowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let controller = LaterWindowViewController()
        window.rootViewController = controller
        // A tracker of the window's own, enriched with a screen, whose ScreenKey wins over the
        // one automatic tracking gives.
        window.traitOverrides.tracker = windowScene.traitCollection.tracker.enriched(by: Enricher { context in
            context[ScreenKey.self] = "Later"
        })
        window.frame = CGRect(x: 0, y: windowScene.screen.bounds.height - 160, width: windowScene.screen.bounds.width, height: 120)
        window.windowLevel = .alert
        window.isHidden = false
        laterWindow = window
    }
}

/// A button class of the app's own, whose kind is still UIKit's "UIButton".
final class CheckoutButton: UIButton {}

final class LaterWindowViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        let button = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Later") { _ in })
        button.accessibilityIdentifier = "later-window-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
