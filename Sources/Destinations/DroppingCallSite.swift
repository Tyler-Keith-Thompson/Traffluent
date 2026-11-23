import Events

extension Destination {
    /// This destination, receiving each record without its call site: `EventRecord.sourceLocation`
    /// is `nil`.
    ///
    /// Every destination receives each record's call site unless it is given this, for one that
    /// shouldn't learn the app's file and function names, a third-party vendor's say.
    ///
    /// - Returns: A destination that hands this one each batch with its records' call sites
    ///   removed.
    public func droppingCallSite() -> some Destination {
        TransformingDestination(base: self) { record in
            var record = record
            record.sourceLocation = nil
            return record
        }
    }
}
