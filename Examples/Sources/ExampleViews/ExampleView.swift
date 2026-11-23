// SwiftUI is on Apple platforms alone; on Linux this module builds empty, so the package
// still does.
#if canImport(SwiftUI)
    public import Trackers
    public import SwiftUI
    import ExampleEvents

    /// The screen every Apple example app shows: a button per label, each tracking
    /// ``ExampleEvents/ButtonTapped`` through the tracker it was given.
    ///
    /// It takes the tracker rather than reading `Tracker.current`: SwiftUI runs button actions on
    /// tasks of its own, which a `withTracker` binding doesn't reach.
    public struct ExampleView: View {
        /// The labels of the buttons the screen shows, top to bottom.
        public static let labels = ["Subscribe", "Share"]

        private let tracker: Tracker

        /// A screen tracking its taps through `tracker`.
        ///
        /// - Parameter tracker: The tracker each tap is tracked through.
        public init(tracker: Tracker) {
            self.tracker = tracker
        }

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
