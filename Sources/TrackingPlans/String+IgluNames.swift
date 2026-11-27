// Iglu's rules for the parts of a schema's URI, from iglu-core's SchemaKey and Iglu Central's
// self-describing meta-schema (iglu:com.snowplowanalytics.self-desc/schema/jsonschema/1-0-0, read
// on 2026-11-27): a vendor matches `^[a-zA-Z0-9-_.]+$` and a name `^[a-zA-Z0-9-_]+$`. Shared with
// SnowplowEncoding, whose encoder writes the URIs this module's export names its files after, so
// the two never disagree on which names Iglu takes or how a version maps to a SchemaVer.

extension String {
    /// Whether the string is an Iglu vendor: one or more ASCII letters, digits, `-` or `_`, in
    /// labels joined by `.`, none of them empty, as in reverse domain notation (`com.acme`).
    ///
    /// Iglu takes a vendor of any of those characters, a leading, trailing or doubled `.` included,
    /// but reverse domain notation never has an empty label, so one is a slip rather than a
    /// vendor. One label alone is taken, as Iglu takes it.
    package var isIgluVendor: Bool {
        // The empty string is one empty label, so it is refused with the rest.
        split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.utf8.allSatisfy(\.isIgluNameByte)
        }
    }

    /// Whether the string is an Iglu schema name: one or more ASCII letters, digits, `-` or `_`.
    package var isIgluName: Bool {
        !isEmpty && utf8.allSatisfy(\.isIgluNameByte)
    }

    /// Whether Iglu can name the schema of version `version` of the event this string names: the
    /// name is an Iglu name and the version is 1 or more, as a SchemaVer's MODEL is.
    package func hasIgluSchemaKey(version: Int) -> Bool {
        isIgluName && version >= 1
    }

    /// The Iglu URI, under `vendor`, of the schema of version `version` of the event this string
    /// names: `iglu:<vendor>/<name>/jsonschema/<version>-0-0`.
    ///
    /// Each version of a Traffluent event is a breaking change, a SchemaVer MODEL, so version N is
    /// `N-0-0`, and events always name it. A compatible change at the same version (an optional
    /// property added, a property removed and kept as deprecated) is an ADDITION, which the Iglu
    /// export writes for Iglu Server as `N-0-1`, `N-0-2` and so on, each superseding the earlier
    /// ones, so the pipeline validates events against the newest. A static repository doesn't
    /// supersede, so the export refuses an addition for one.
    package func igluSchemaURI(vendor: String, version: Int) -> String {
        "iglu:\(vendor)/\(self)/jsonschema/\(String.igluSchemaVersion(model: version, addition: 0))"
    }

    /// A SchemaVer of `model` and `addition`, with no revision: `<model>-0-<addition>`.
    package static func igluSchemaVersion(model: Int, addition: Int) -> String {
        "\(model)-0-\(addition)"
    }
}

extension UInt8 {
    /// ASCII letters, digits, `-` and `_`.
    fileprivate var isIgluNameByte: Bool {
        (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self) || self == 0x2D || self == 0x5F
    }
}
