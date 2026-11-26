#if canImport(UIKit) && !os(watchOS)
    import AutomaticControlTracking
    import AutomaticScreenTracking
    public import SwiftUI
    import SwiftUITracking
    public import Trackers
    import UIKit
    import UIKitTracking

    extension View {
        /// Gives the window scene this view is shown in `tracker` as its trait, and turns on its
        /// automatic screen and control tracking.
        ///
        /// A SwiftUI app has no scene delegate of its own to do it in, so this finds the scene
        /// through a view placed behind this one. Only UIKit's view controllers are tracked as
        /// screens: the SwiftUI screens track themselves with `trackScreen(_:)`. The checkout's
        /// view controller is tracked as `Checkout`, the name the SwiftUI checkout has where
        /// UIKit isn't.
        ///
        /// - Parameter tracker: The tracker the scene's screens and controls track through.
        /// - Returns: The view, turning automatic tracking on in its scene.
        public func trackWindowSceneAutomatically(_ tracker: Tracker) -> some View {
            background(WindowSceneReader { scene in
                scene.traitOverrides.tracker = tracker
                scene.trackScreensAutomatically(kinds: [.uiKit]) { screen in
                    ScreenViewed(screen: screen.name == "CheckoutViewController" ? "Checkout" : screen.name)
                }
                scene.trackControlsAutomatically()
            })
        }
    }

    /// An empty view that hands over the window scene it is shown in, each time it moves to a
    /// window.
    private struct WindowSceneReader: UIViewRepresentable {
        let sceneFound: @MainActor (UIWindowScene) -> Void

        func makeUIView(context: Context) -> ReaderView {
            ReaderView(sceneFound: sceneFound)
        }

        func updateUIView(_ view: ReaderView, context: Context) {}

        final class ReaderView: UIView {
            private let sceneFound: @MainActor (UIWindowScene) -> Void

            init(sceneFound: @escaping @MainActor (UIWindowScene) -> Void) {
                self.sceneFound = sceneFound
                super.init(frame: .zero)
            }

            required init?(coder: NSCoder) { nil }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                if let scene = window?.windowScene {
                    sceneFound(scene)
                }
            }
        }
    }
#endif
