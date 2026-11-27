import Foundation

extension UUID {
    /// The UUID as a Matomo visitor ID, `_id`: its last 64 bits as 16 lowercase hexadecimal
    /// digits.
    ///
    /// Matomo takes a visitor ID of exactly 16 hexadecimal digits, 64 bits, so a UUID's 128 don't
    /// fit. The last 64 are random in a version 4 and a version 7 UUID alike, but for the two
    /// variant bits.
    // Rejected: the first 64 bits. Of a version 7 UUID, a SessionKey, they are 48 bits of the
    // session's start in milliseconds and 12 random bits, so sessions started in the same
    // millisecond on two devices would share a visitor one time in 4,096. Rejected too: a hash of
    // all 128 bits, which gives no fewer collisions in practice than the 62 random bits of the last
    // 64 taken here.
    var matomoVisitorID: String {
        let bytes = uuid
        let digits = Array("0123456789abcdef".utf8)
        var text: [UInt8] = []
        text.reserveCapacity(16)
        for byte in [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15] {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: text, as: UTF8.self)
    }
}
