// Compiled for macOS and Linux alone, as the factory is (HTTPDestination+GoogleAnalytics.swift), so
// nothing in this module can write a Measurement Protocol request in an app for iOS, iPadOS, tvOS,
// watchOS, visionOS or Mac Catalyst.
#if os(macOS) || os(Linux)
// From the Measurement Protocol reference and guide, read on 2026-11-27:
// https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference ("Reserved
// names") and https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events
// ("Limitations": names "40 characters or fewer, can only contain alphanumeric characters and
// underscores, and must start with an alphabetic character"). The validation server
// (/debug/mp/collect, the same day) counts the 40 in bytes of UTF-8, takes letters of any script
// and, after the first, numbers of any kind ("café_open", "中文", "a٣", "a²", "aⅣ"), refuses a
// combining mark, a symbol and punctuation but `_`, and treats the reserved
// names and prefixes case-sensitively ("GA_p" and "Session_Start" pass).
extension String {
    /// Whether Google Analytics takes this as an event's or a parameter's name: 1 to 40 bytes of
    /// UTF-8, starting with a letter, and holding only letters, numbers and `_`.
    var isMeasurementProtocolName: Bool {
        guard let first = unicodeScalars.first, utf8.count <= 40, first.isLetter else { return false }
        return unicodeScalars.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Whether Google Analytics keeps this event name: one of the reserved names the reference
    /// lists, or one it takes only from an app stream, which a web or data stream's
    /// `measurement_id` isn't.
    var isReservedMeasurementProtocolEventName: Bool {
        Self.reservedEventNames.contains(self)
    }

    /// Whether Google Analytics keeps this parameter name, or the encoder writes it:
    /// `firebase_conversion`, a `firebase_`, `ga_` or `google_` prefix, and `session_id`.
    ///
    /// A name starting with `_` or `gtag.`, prefixes the reference also reserves, is no name at
    /// all (`isMeasurementProtocolName`).
    var isReservedMeasurementProtocolParameterName: Bool {
        // The reference's reserved firebase_conversion has the firebase_ prefix, so the prefix
        // covers it.
        self == "session_id" || hasPrefix("firebase_") || hasPrefix("ga_") || hasPrefix("google_")
    }

    private static let reservedEventNames: Set<String> = [
        "ad_activeview", "ad_click", "ad_exposure", "ad_query", "ad_reward", "adunit_exposure",
        "app_clear_data", "app_exception", "app_install", "app_remove", "app_store_refund",
        "app_update", "app_upgrade", "dynamic_link_app_open", "dynamic_link_app_update",
        "dynamic_link_first_open", "error", "firebase_campaign", "firebase_in_app_message_action",
        "firebase_in_app_message_dismiss", "firebase_in_app_message_impression", "first_open",
        "first_visit", "notification_dismiss", "notification_foreground", "notification_open",
        "notification_receive", "notification_send", "os_update", "session_start",
        "user_engagement",
        // "ad_impression, in_app_purchase and screen_view events are only allowed for App streams".
        // The validation server refuses only in_app_purchase on a web stream, but the reference
        // allows none of them there.
        "ad_impression", "in_app_purchase", "screen_view",
    ]
}

extension Unicode.Scalar {
    /// Whether the scalar is a letter of any script: general category L (Lu, Ll, Lt, Lm or Lo).
    fileprivate var isLetter: Bool {
        switch properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }

    /// Whether the scalar is a number of any script: general category Nd, Nl or No.
    fileprivate var isNumber: Bool {
        switch properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: true
        default: false
        }
    }
}
#endif
