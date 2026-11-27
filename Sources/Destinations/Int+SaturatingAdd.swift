// The same few lines as Trackers' own, duplicated: sharing them would mean package API in a
// module both depend on, coupling the two for a helper shorter than its import.
extension Int {
    /// The sum of this count and `other`, held at `Int.max` or `Int.min` where it would pass them,
    /// so a merged report's count stops growing rather than trapping.
    ///
    /// - Parameter other: The count to add.
    /// - Returns: `self + other`, or the bound it passes.
    func saturatingAdd(_ other: Int) -> Int {
        // Comparisons rather than addingReportingOverflow, whose result would be thrown away on
        // overflow. Each bound is computed on the side where it can't overflow itself.
        if other >= 0 {
            guard self <= Int.max - other else { return Int.max }
            return self + other
        }
        guard self >= Int.min - other else { return Int.min }
        return self + other
    }
}
