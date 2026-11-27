import Foundation

// From Aptabase's server, github.com/aptabase/aptabase at 89d36185 (read 2026-11-27):
// src/Features/Apps/AppsController.cs makes a key as $"A-{_env.Region}-{NanoId.Numbers(10)}", and
// src/Features/EnvSettings.cs sets the region to "DEV" in development, to the REGION variable
// upper-cased otherwise, and to "SH" when that is empty; its cloud runs as "EU" and "US"
// (IsManagedCloud). Its Swift SDK, github.com/aptabase/aptabase-swift at a1ee53e9
// (Sources/Aptabase/Aptabase.swift), splits the key on "-", takes three parts with the region in
// [US, EU, DEV, SH] as written, and sends US and EU keys to https://us.aptabase.com and
// https://eu.aptabase.com, and SH keys to the host the app gives.
/// Where an app key's events go, from the key's region.
enum AptabaseRegion: Sendable, Hashable {
    /// Aptabase's cloud in the European Union: `https://eu.aptabase.com`.
    case eu
    /// Aptabase's cloud in the United States: `https://us.aptabase.com`.
    case us
    /// A server of the app's own, at the host the app gives: a self-hosted server's key
    /// (`A-SH-`), or a development server's (`A-DEV-`).
    case selfHosted

    /// The region of `appKey`, already trimmed.
    ///
    /// - Throws: ``AptabaseSetupError/emptyAppKey`` for an empty key,
    ///   ``AptabaseSetupError/malformedAppKey`` for one that isn't `A-<region>-<body>` with a body
    ///   of ASCII letters and digits, and ``AptabaseSetupError/unknownRegion`` for a region other
    ///   than `EU`, `US`, `SH` and `DEV`.
    init(appKey: String) throws(AptabaseSetupError) {
        guard !appKey.isEmpty else { throw .emptyAppKey }
        let parts = appKey.split(separator: "-", omittingEmptySubsequences: false)
        // The server makes a body of 10 digits, but the SDKs check only the region, so a body is
        // refused only when no server could have made it: empty, or holding anything but ASCII
        // letters and digits (a space, a quote, a URL pasted in its place).
        guard parts.count == 3, parts[0] == "A", !parts[2].isEmpty, parts[2].utf8.allSatisfy(\.isASCIILetterOrDigit) else {
            throw .malformedAppKey
        }
        switch parts[1] {
        case "EU": self = .eu
        case "US": self = .us
        // A development server's key is taken as a self-hosted one: the SDKs send it to
        // http://localhost:3000, a server on the developer's own machine, which the app names.
        case "SH", "DEV": self = .selfHosted
        default: throw .unknownRegion
        }
    }
}

extension UInt8 {
    /// Whether the byte is an ASCII letter or digit.
    fileprivate var isASCIILetterOrDigit: Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(self)
            || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(self)
            || (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(self)
    }
}
