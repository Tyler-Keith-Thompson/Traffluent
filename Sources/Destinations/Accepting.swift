public import Events

extension Destination {
    /// This destination, receiving only the events in `categories`.
    ///
    /// ```swift
    /// let delivery = tracker.records.batch().deliver(
    ///     to: productAnalytics,
    ///     adNetwork.accepting(.advertising)
    /// )
    /// ```
    ///
    /// A destination that declares nothing receives every category a tracker's consent lets
    /// through; this narrows it to the purposes it serves. An event reaches it only if its
    /// category is both consented and accepted. Applied twice, it accepts the categories both
    /// accept. A batch with no accepted record isn't handed to it.
    ///
    /// - Parameter categories: The categories to receive; none means it receives nothing.
    /// - Returns: A destination that hands this one each batch's records of those categories.
    public func accepting(_ categories: ConsentCategory...) -> some Destination {
        let accepted = Set(categories)
        return TransformingDestination(base: self) { record in
            accepted.contains(record.consentCategory) ? record : nil
        }
    }
}
