// From TelemetryDeck's Ingest API v3 reference, https://telemetrydeck.com/docs/ingest/v3/ (the
// docs' source, github.com/TelemetryDeck/docs, docs/ingest/v3.md at 1389edf3), and its default
// parameters, https://telemetrydeck.com/docs/ingest/default-parameters/, read on 2026-11-27: "A
// type may only contain letters, digits, dots, underscores, and hyphens", "A key may only contain
// letters, digits, dots, underscores, and hyphens. The events endpoint rejects an event with any
// other key", "A namespace may only contain letters, digits, dots, underscores, and hyphens", "The
// path segment `w` is reserved for the web endpoint", "The server does not rename or clean your
// keys in v3", and "avoid using parameter names that begin with the `TelemetryDeck.` scope, as
// this is reserved for parameters set by TelemetryDeck SDKs and the ingestion server"; the default
// parameters' list of reserved parameters holds only names in that scope. v3 rejects no other
// name, so the encoder refuses only that scope and, for a parameter, the event's own members it
// would replace. The endpoint, the same day, counted only ASCII letters: it answered 422 "Invalid
// key 'bé': keys may only contain letters, digits, '.', '_' and '-'", and the same for an empty
// key and a namespace holding a space.
extension String {
    /// Whether TelemetryDeck takes this as an event's `type` or a parameter's key: one or more
    /// ASCII letters, digits, `.`, `_` and `-`.
    var isTelemetryDeckName: Bool {
        !isEmpty && utf8.allSatisfy(\.isTelemetryDeckNameByte)
    }

    /// Whether TelemetryDeck takes this as a namespace in its endpoint's path: a name it takes,
    /// but not `w`, the web endpoint's path, nor `.` or `..`, which a URL's path reads as no
    /// segment.
    var isTelemetryDeckNamespace: Bool {
        isTelemetryDeckName && self != "w" && self != "." && self != ".."
    }

    /// Whether the name is in the `TelemetryDeck.` scope, in any case, which TelemetryDeck
    /// reserves for its SDKs' parameters and its server's.
    var isInTelemetryDeckScope: Bool {
        lowercased().hasPrefix("telemetrydeck.")
    }

    /// Whether a parameter of this name can't be sent: one in the `TelemetryDeck.` scope, or one
    /// of an Ingest API v3 event's own members, which sit beside the parameters in the flat event,
    /// so a parameter of the name would replace the member.
    var isReservedByTelemetryDeck: Bool {
        isInTelemetryDeckScope || Self.eventMembers.contains(self)
    }

    /// The members of an Ingest API v3 event, the required and the optional, as its reference
    /// lists them. JSON's names are case-sensitive, so only these spellings collide.
    private static let eventMembers: Set<String> = [
        "appID", "clientUser", "receivedAt", "type", "sessionID", "isTestMode", "floatValue",
    ]
}

extension UInt8 {
    /// Whether the byte is an ASCII letter, digit, `.`, `_` or `-`.
    fileprivate var isTelemetryDeckNameByte: Bool {
        switch self {
        case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "0") ... UInt8(ascii: "9"):
            true
        case UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "-"):
            true
        default:
            false
        }
    }
}
