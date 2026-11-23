extension TrackingPlan {
    /// One file of a tracking plan: its path within the plan's directory and its bytes.
    public struct File: Sendable, Hashable {
        /// The file's path, relative to the directory the plan is written to.
        public let path: String
        /// The file's UTF-8 JSON, ending in a newline.
        public let contents: [UInt8]
    }
}
