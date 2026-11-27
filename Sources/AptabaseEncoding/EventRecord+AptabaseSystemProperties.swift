import Events
import Foundation
import Instrumentation
import StandardContext

// The members and their limits are Aptabase's SystemProperties (github.com/aptabase/aptabase at
// 89d36185, src/Features/Ingestion/EventBody.cs, read 2026-11-27): OSName 30, OSVersion 100,
// Locale 10, AppVersion 50, AppBuildNumber 20, DeviceModel 100, each a [StringLength] its model
// validation checks, answering 400 for the whole request past one. Its Swift SDK
// (github.com/aptabase/aptabase-swift at a1ee53e9, EnvironmentInfo.swift) sends the same names:
// the system's name and version, the language code, CFBundleShortVersionString,
// CFBundleVersion and the hardware model.
extension EventRecord {
    /// Aptabase's system properties for the library's own context keys the record holds a value
    /// for, by the member's name: all but `isDebug` and `sdkVersion`, which the encoder adds.
    ///
    /// Only what Aptabase has a member for. The bundle identifier, the form factor and the network
    /// aren't sent: Aptabase has no member for them. Not the vendor identifier, the sample rate or
    /// the trace context either: the session is the only identifier Aptabase is sent (D4).
    var aptabaseSystemProperties: [String: String] {
        var members: [String: String] = [:]
        if let operatingSystem = context[OperatingSystemKey.self] {
            members["osName"] = operatingSystem.name
            members["osVersion"] = operatingSystem.version
        }
        if let application = context[ApplicationKey.self] {
            members["appVersion"] = application.version
            members["appBuildNumber"] = application.build
        }
        if let device = context[DeviceKey.self] {
            members["deviceModel"] = device.model
        }
        if let locale = context[LocaleKey.self]?.aptabaseLocale {
            members["locale"] = locale
        }
        return members
    }
}

extension Locale {
    /// The locale as Aptabase takes it: its language and region (`en-US`, `es-419`), its language
    /// alone (`en`) when it has no region or the two are over Aptabase's 10 characters, and `nil`
    /// when even the language is.
    ///
    /// Aptabase's server reads a locale of 2 letters, or a language of 2 letters with a region or
    /// a script and a region (`zh-Hans-CN`), and stores any other form as empty, but refuses the
    /// whole request for one over 10 characters. A script, variant or extension (`-u-ca-buddhist`,
    /// which a person's calendar setting adds) is left out, so a locale never costs a record.
    /// Rejected: sending the language code alone, as Aptabase's Swift SDK does, which loses the
    /// region Aptabase's dashboard can show.
    var aptabaseLocale: String? {
        guard let language = language.languageCode?.identifier else { return nil }
        if let region = region?.identifier {
            let tagged = "\(language)-\(region)"
            if tagged.utf16.count <= 10 {
                return tagged
            }
        }
        return language.utf16.count <= 10 ? language : nil
    }
}
