import Foundation

// From Matomo's tracker, matomo-org/matomo 6.0.0 (and the same in 5.14.3), read on 2026-11-27:
// core/Common.php's getRequestVar reads each string parameter through sanitizeInputValue, which
// removes "\n" and "\r" (sanitizeLineBreaks) and "\0" (sanitizeNullBytes) and escapes the value
// with htmlspecialchars(ENT_QUOTES), so `&`, `<`, `>`, `"` and `'` are stored as `&amp;`, `&lt;`,
// `&gt;`, `&quot;` and `&#039;`; plugins/Events/Columns/EventCategory.php, EventAction.php and
// EventName.php trim the value and refuse an empty category or action
// (InvalidRequestParameterException, which bulk tracking counts as invalid and answers 200 for);
// core/Db/Schema/Mysql.php stores it in log_action.name, a VARCHAR(4096), under sql_mode
// NO_AUTO_VALUE_ON_ZERO alone (core/Db.php), which cuts a longer value short without an error;
// and plugins/CustomDimensions/Tracker/CustomDimensionsRequestProcessor.php keeps
// mb_substr(trim($value), 0, 250) of a dimension's value. Before escaping, sanitizeString runs
// html_entity_decode, so entity text already in the value (`&amp;`, `&eacute;`, `&#8364;`) becomes
// one character before it is escaped again, and this count, which doesn't decode, is higher than
// Matomo's by up to the entity's length less one, or less after escaping. The count is never
// below Matomo's, so a value near a limit that holds entity text may be skipped though Matomo
// would have kept it whole, but no value is ever sent that Matomo cuts short. Rejected: decoding
// entities here, which needs PHP's whole entity table to match Matomo exactly.
extension String {
    /// The value as Matomo stores a string parameter: without line breaks or NUL characters, with
    /// `&`, `<`, `>`, `"` and `'` as HTML entities, and trimmed as PHP's `trim` trims, of spaces,
    /// tabs, line breaks, NULs and vertical tabs.
    var matomoStoredValue: String {
        var escaped = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            switch scalar {
            case "\n", "\r", "\0": continue
            case "&": escaped.append(contentsOf: "&amp;".unicodeScalars)
            case "<": escaped.append(contentsOf: "&lt;".unicodeScalars)
            case ">": escaped.append(contentsOf: "&gt;".unicodeScalars)
            case "\"": escaped.append(contentsOf: "&quot;".unicodeScalars)
            case "'": escaped.append(contentsOf: "&#039;".unicodeScalars)
            default: escaped.append(scalar)
            }
        }
        var start = escaped.startIndex
        var end = escaped.endIndex
        while start < end, escaped[start].isTrimmedByPHP {
            start = escaped.index(after: start)
        }
        while start < end, escaped[escaped.index(before: end)].isTrimmedByPHP {
            end = escaped.index(before: end)
        }
        return String(String.UnicodeScalarView(escaped[start ..< end]))
    }

    /// The characters Matomo stores of the value, as MySQL counts them in a `utf8mb4` column: one
    /// per Unicode scalar of ``matomoStoredValue``.
    var matomoStoredLength: Int {
        matomoStoredValue.unicodeScalars.count
    }

    /// The string with every character but an unreserved one (RFC 3986: ASCII letters, digits,
    /// `-`, `.`, `_`, `~`) as percent escapes of its UTF-8, so it can't end a query's value, and
    /// PHP's `parse_str` reads it back as it is: `+` is escaped, which PHP would read as a space.
    // The same escaping as GoogleAnalyticsEncoding's, written again rather than shared: a few lines
    // cost less than a public API in PropertyJSON.
    var percentEncodedForQuery: String {
        // nil only for a string that isn't valid Unicode, which a Swift String never is.
        addingPercentEncoding(withAllowedCharacters: .urlUnreserved) ?? self
    }
}

extension Unicode.Scalar {
    /// Whether PHP's `trim` removes the character from either end of a string: a space, a tab, a
    /// line feed, a carriage return, a NUL or a vertical tab.
    fileprivate var isTrimmedByPHP: Bool {
        switch self {
        case " ", "\t", "\n", "\r", "\0", "\u{0B}": true
        default: false
        }
    }
}

extension CharacterSet {
    /// RFC 3986's unreserved characters, the only ones a query's value holds unescaped whatever
    /// reads it.
    fileprivate static let urlUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
