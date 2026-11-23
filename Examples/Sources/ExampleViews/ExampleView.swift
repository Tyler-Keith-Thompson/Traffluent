// SwiftUI is on Apple platforms alone; on Linux this module builds empty, so the package
// still does.
#if canImport(SwiftUI)
    import Trackers
    public import SwiftUI
    import SwiftUITracking
    import ExampleEvents

    /// The screen every Apple example app shows: a button per label, each tracking
    /// ``ExampleEvents/ButtonTapped`` through the environment's tracker.
    ///
    /// It reads the tracker from the environment, which the app sets at its root with
    /// `tracker(_:)`, rather than `Tracker.current`: SwiftUI runs button actions on tasks of its
    /// own, which a `withTracker` binding doesn't reach, but an action reads the environment of
    /// the view it is in. The app places it with `trackScreen(_:)`, so that tracker is enriched
    /// with the screen's name and each tap's record carries it as its `ScreenKey`. The modifier
    /// goes where the view is placed, not in its own body: a view's `@Environment` reads the
    /// environment around it, which its own body's modifiers don't change.
    public struct ExampleView: View {
        /// The labels of the buttons the screen shows, top to bottom.
        public static let labels = ["Subscribe", "Share"]

        @Environment(\.tracker) private var tracker

        /// The screen.
        public init() {}

        public var body: some View {
            VStack(spacing: 12) {
                Text("Traffluent")
                    .font(.headline)
                ForEach(Self.labels, id: \.self) { label in
                    Button(label) {
                        tracker.track(ButtonTapped(label: label))
                    }
                }
            }
            .padding()
        }
    }
#endif
