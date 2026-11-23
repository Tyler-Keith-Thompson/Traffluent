import Events

extension Destination {
    /// This destination, receiving each record with its `Sensitive` values redacted:
    /// `EventRecord.reveal(_:)` gives `nil` for every one.
    ///
    /// ```swift
    /// let delivery = tracker.records.batch().deliver(
    ///     to: ownBackend,
    ///     vendor.redactingSensitiveValues()
    /// )
    /// ```
    ///
    /// Every destination can reveal a record's sensitive values unless it is given this. The
    /// event itself is unchanged: its other properties, its name and its category arrive as
    /// tracked.
    ///
    /// - Returns: A destination that hands this one each batch with its records redacted.
    public func redactingSensitiveValues() -> some Destination {
        TransformingDestination(base: self) { record in
            var record = record
            record.revealsSensitiveValues = false
            return record
        }
    }
}
