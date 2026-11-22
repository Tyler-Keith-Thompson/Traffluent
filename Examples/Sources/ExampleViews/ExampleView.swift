// SwiftUI is on Apple platforms alone; on Linux and Wasm this module builds empty, so the package
// still does.
#if canImport(SwiftUI)
    public import Pipelines
    public import SwiftUI
    import ExampleEvents

    /// The screen every Apple example app shows: a button per label, each tracking
    /// ``ExampleEvents/ButtonTapped`` through the pipeline it was given.
    public struct ExampleView: View {
        /// The labels of the buttons the screen shows, top to bottom.
        public static let labels = ["Subscribe", "Share"]

        private let pipeline: Pipeline

        /// A screen tracking its taps through `pipeline`.
        ///
        /// - Parameter pipeline: The pipeline each tap is tracked through.
        public init(pipeline: Pipeline) {
            self.pipeline = pipeline
        }

        public var body: some View {
            VStack(spacing: 12) {
                Text("Traffluent")
                    .font(.headline)
                ForEach(Self.labels, id: \.self) { label in
                    Button(label) {
                        Task { await pipeline.track(ButtonTapped(label: label)) }
                    }
                }
            }
            .padding()
        }
    }
#endif
