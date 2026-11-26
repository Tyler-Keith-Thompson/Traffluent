// Saturating arithmetic for the cart's counts and prices: a sum or product past `Int`'s range
// stops at its bound rather than trapping. No cart comes near it, but the inputs are public
// values, and a total stuck at `Int.max` is a visible wrong answer where a trap is a crash.
extension Int {
    /// `self + other`, or the nearest bound of `Int` when that overflows.
    func saturatingAdding(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        guard overflow else { return sum }
        return other > 0 ? .max : .min
    }

    /// `self - other`, or the nearest bound of `Int` when that overflows.
    func saturatingSubtracting(_ other: Int) -> Int {
        let (difference, overflow) = subtractingReportingOverflow(other)
        guard overflow else { return difference }
        return other < 0 ? .max : .min
    }

    /// `self * other`, or the nearest bound of `Int` when that overflows.
    func saturatingMultiplied(by other: Int) -> Int {
        let (product, overflow) = multipliedReportingOverflow(by: other)
        guard overflow else { return product }
        return (self < 0) == (other < 0) ? .max : .min
    }
}
