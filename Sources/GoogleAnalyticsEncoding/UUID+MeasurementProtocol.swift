// Compiled for macOS and Linux alone, as the factory is (HTTPDestination+GoogleAnalytics.swift), so
// nothing in this module can write a Measurement Protocol request in an app for iOS, iPadOS, tvOS,
// watchOS, visionOS or Mac Catalyst.
#if os(macOS) || os(Linux)
import Foundation

extension UUID {
    /// The UUID as a Measurement Protocol `client_id`: its first 64 bits and its last 64 bits, each
    /// as an unsigned decimal number, joined by a period.
    ///
    /// The validation server refuses a `client_id` in any other form ("It should be in
    /// <number>.<number> format", checked on 2026-11-27), so the UUID's own string isn't sent. The
    /// two halves hold every bit, so two sessions never share a client.
    var measurementProtocolClientID: String {
        let bytes = uuid
        let high = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = [bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return "\(high).\(low)"
    }

    /// The first 48 bits of a version 7 UUID, its time in Unix milliseconds, as the Measurement
    /// Protocol's `session_id`; `nil` for a UUID of any other version or variant, whose first bits
    /// are no time.
    // The same reading as AmplitudeEncoding's, duplicated rather than shared: a few lines cost less
    // than a public API in PropertyJSON that one more vendor would need.
    var version7Milliseconds: Int64? {
        let bytes = uuid
        // RFC 9562: the version is the high nibble of byte 6, and the variant the top two bits of
        // byte 8, `10`.
        guard bytes.6 >> 4 == 7, bytes.8 >> 6 == 0b10 else { return nil }
        return [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5].reduce(Int64(0)) { $0 << 8 | Int64($1) }
    }
}
#endif
