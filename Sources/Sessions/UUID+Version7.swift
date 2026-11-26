import Foundation

// Foundation has no UUIDv7 initializer, on Apple platforms or in swift-foundation, so this is
// RFC 9562's layout written out; replace it with Foundation's once one ships everywhere the
// library builds.
extension UUID {
    /// A version 7 UUID (RFC 9562, section 5.7) for a session that starts at `date`.
    ///
    /// The first 48 bits are `date` in Unix milliseconds, clamped to 0 through 2^48 - 1; then
    /// come the version (7) and the variant (`10`), and the other 74 bits are random.
    ///
    /// - Parameter date: When the session starts.
    init(version7At date: Date) {
        let maximum: UInt64 = 0xFFFF_FFFF_FFFF
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded(.down)
        // Clamped as a Double before converting, so a date outside 1970 to 10889 can't trap.
        let timestamp = milliseconds.isNaN ? 0 : UInt64(Swift.min(Swift.max(milliseconds, 0), Double(maximum)))
        var generator = SystemRandomNumberGenerator()
        let high = generator.next() as UInt64
        let low = generator.next() as UInt64
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: timestamp >> (8 * (5 - index)))
        }
        for index in 6..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: high >> (8 * index))
        }
        for index in 8..<16 {
            bytes[index] = UInt8(truncatingIfNeeded: low >> (8 * (index - 8)))
        }
        bytes[6] = 0x70 | (bytes[6] & 0x0F)
        bytes[8] = 0x80 | (bytes[8] & 0x3F)
        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
