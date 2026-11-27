# Planted bugs for TelemetryDeckEncoding; run with `just mutate TelemetryDeckEncoding`. See
# scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/TelemetryDeckEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Mutants are applied in this order, so one whose `old`
# holds another's comes first. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The properties PropertyJSON reads (its PropertyReader), flattening, identity and batch
#   splitting: PropertyJSON's spec plants those.
# - The unknownEvent arm of `TelemetryDeckEncodingError.init(_ error: PropertyReadingError)`
#   mapped to another case: the catch in json(of:) only reaches it for an event the plan doesn't
#   describe, and the unknownEvent tests pin the case it maps to.
# - The catch of iso8601Timestamp: the guard before it already refuses every timestamp the
#   conversion would, so it is never taken.
# - The `let endpoint = URL(string:)` condition of the factory's guard: a namespace that passes
#   isTelemetryDeckNamespace always makes a URL.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
# - `text.reserveCapacity(64)` in sha256Hex: capacity alone changes no result.
# - Mutants only a case pattern, an `if let` list of conditions or a set literal could hold, which
#   mutate.py's expression and statement switches can't: a byte range of isTelemetryDeckNameByte
#   narrowed, versionAndBuildNumber sent with one of the two, or one event member's name dropped.
#   The name tests list each range's ends and each member's name, and the context tests a version
#   or build alone.
# - The notices the encoder's initializer logs for names TelemetryDeck refuses or reserves: logs
#   are for developers, and tests don't pin them (AGENTS.md, Logging).

TESTS = ["TelemetryDeckEncodingTests"]

B = "TelemetryDeckBatchEncoder.swift"
C = "EventRecord+TelemetryDeckContext.swift"
F = "HTTPDestination+TelemetryDeck.swift"
N = "String+TelemetryDeckNames.swift"

LIMIT = "BatchLimit(maximumRecordCount: 100, maximumByteCount: 1_000_000, maximumRecordByteCount: 333_333)"
ENCODER = "TelemetryDeckBatchEncoder(appID: appID, testMode: testMode, plan: plan)"
NAME_CHECK_ON_FAILURE = "if case .unknownEvent = error {} else {\n                try record.checkTelemetryDeckName()\n            }"
SESSION_ID = 'if case .session = identity {\n            event["sessionID"] = .string(identifier)\n        }'

MUTANTS = [
    # The limits.
    Mutant("batchcount101", B, LIMIT, "BatchLimit(maximumRecordCount: 101, maximumByteCount: 1_000_000, maximumRecordByteCount: 333_333)"),
    Mutant("batchcount99", B, LIMIT, "BatchLimit(maximumRecordCount: 99, maximumByteCount: 1_000_000, maximumRecordByteCount: 333_333)"),
    Mutant("batchbytes1000001", B, LIMIT, "BatchLimit(maximumRecordCount: 100, maximumByteCount: 1_000_001, maximumRecordByteCount: 333_333)"),
    Mutant("batchbytes999999", B, LIMIT, "BatchLimit(maximumRecordCount: 100, maximumByteCount: 999_999, maximumRecordByteCount: 333_333)"),
    Mutant("recordbytes333334", B, LIMIT, "BatchLimit(maximumRecordCount: 100, maximumByteCount: 1_000_000, maximumRecordByteCount: 333_334)"),
    Mutant("recordbytes333332", B, LIMIT, "BatchLimit(maximumRecordCount: 100, maximumByteCount: 1_000_000, maximumRecordByteCount: 333_332)"),
    Mutant("oversizedbytecount", B, ".oversized(byteCount: byteCount)", "TelemetryDeckEncodingError.oversized(byteCount: 0)"),
    Mutant("limitignored", B, "self.limit = limit", "self.limit = TelemetryDeckBatchEncoder.batchLimit", mode="stmt"),

    # The setup checks.
    Mutant("untrimmedappid", B, "appID.trimmingCharacters(in: .whitespacesAndNewlines)", "appID"),
    Mutant("emptyappid", B, "!appID.isEmpty", "true"),
    Mutant("anynamespace", F, "namespace.isTelemetryDeckNamespace", "true"),
    Mutant("namespaceanyname", N, 'isTelemetryDeckName && self != "w"', 'self != "w"'),
    # The second occurrence, the original; the first is namespaceanyname's replacement.
    Mutant("namespacew", N, 'self != "w"', "true", nth=1),
    Mutant("namespacedotdot", N, 'self != ".."', "true"),
    # The first occurrence: the second is inside `self != ".."`.
    Mutant("namespacedot", N, 'self != "."', "true", nth=0),
    Mutant("v2endpoint", F, '"https://nom.telemetrydeck.com/v3/\\(namespace)/"', '"https://nom.telemetrydeck.com/v2/namespace/\\(namespace)/"'),
    Mutant("noslash", F, '"https://nom.telemetrydeck.com/v3/\\(namespace)/"', '"https://nom.telemetrydeck.com/v3/\\(namespace)"'),
    Mutant("testmodedropped", F, ENCODER, "TelemetryDeckBatchEncoder(appID: appID, testMode: false, plan: plan)"),

    # The name rules.
    Mutant("emptyname", N, "!isEmpty && utf8.allSatisfy(\\.isTelemetryDeckNameByte)", "utf8.allSatisfy(\\.isTelemetryDeckNameByte)"),
    Mutant("anybytes", N, "!isEmpty && utf8.allSatisfy(\\.isTelemetryDeckNameByte)", "!isEmpty"),
    Mutant("unicodeletters", N, "utf8.allSatisfy(\\.isTelemetryDeckNameByte)", 'unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0.properties.numericType != nil || "._-".unicodeScalars.contains($0) }', nth=1),
    Mutant("noscope", N, 'lowercased().hasPrefix("telemetrydeck.")', "false"),
    Mutant("scopewithoutdot", N, 'lowercased().hasPrefix("telemetrydeck.")', 'lowercased().hasPrefix("telemetrydeck")'),
    Mutant("scopeanywhere", N, 'lowercased().hasPrefix("telemetrydeck.")', 'lowercased().contains("telemetrydeck.")'),
    # The third occurrence, the original; the first two are in the replacements above.
    Mutant("casesensitivescope", N, "lowercased()", "self", nth=2),
    Mutant("nomembers", N, "Self.eventMembers.contains(self)", "false"),
    Mutant("membersanycase", N, "Self.eventMembers.contains(self)", "Self.eventMembers.contains { $0.lowercased() == lowercased() }"),
    Mutant("membersprefixes", N, "Self.eventMembers.contains(self)", "Self.eventMembers.contains { hasPrefix($0) }"),

    # The skipped records and their order.
    # The second occurrence, after a record is read; the first is in the reader's catch.
    Mutant("namenotchecked", B, "try record.checkTelemetryDeckName()", "", mode="stmt", nth=1),
    Mutant("namecheckedwhenunknown", B, NAME_CHECK_ON_FAILURE, "try record.checkTelemetryDeckName()", mode="stmt"),
    Mutant("namenotcheckedonfailure", B, NAME_CHECK_ON_FAILURE, "", mode="stmt"),
    # The third occurrence, in checkTelemetryDeckName: the first two are the initializer's notices.
    Mutant("invalideventname", B, "name.isTelemetryDeckName", "true", nth=2),
    # The second occurrence, in checkTelemetryDeckName: the first is the initializer's notice.
    Mutant("scopedeventname", B, "name.isInTelemetryDeckScope", "false", nth=1),
    Mutant("eventnamemembers", B, "name.isInTelemetryDeckScope", "name.isReservedByTelemetryDeck", nth=1),
    Mutant("nullskept", B, "$0.value != .null", "true"),
    Mutant("collisionkey", B, "error.key", '""'),
    Mutant("unsortednames", B, "event.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }", "Array(event.keys)"),
    Mutant("descendingnames", B, "$0.utf8.lexicographicallyPrecedes($1.utf8)", "$1.utf8.lexicographicallyPrecedes($0.utf8)"),
    Mutant("anyparametername", B, "names.first(where: { !$0.isTelemetryDeckName })", "nil"),
    Mutant("noreservedparameter", B, "names.first(where: \\.isReservedByTelemetryDeck)", "nil"),
    Mutant("noearliest", B, "seconds >= Self.earliestSeconds", "true"),
    Mutant("noend", B, "seconds < Self.endSeconds", "true"),
    Mutant("earliestexclusive", B, "seconds >= Self.earliestSeconds", "seconds > Self.earliestSeconds"),
    Mutant("endinclusive", B, "seconds < Self.endSeconds", "seconds <= Self.endSeconds"),
    Mutant("earliestyear0", B, "-62_135_596_800", "-62_167_219_200"),
    Mutant("endyear9998", B, "253_402_300_800", "253_370_764_800"),
    Mutant("sensitivesent", B, "properties = try reader.properties(of: record, includingSensitiveValues: false)", "properties = try reader.properties(of: record, includingSensitiveValues: record.revealsSensitiveValues)", mode="stmt"),

    # The signal's members.
    Mutant("sessionidalways", B, SESSION_ID, 'event["sessionID"] = .string(identifier)', mode="stmt"),
    # The second occurrence, the original; the first is sessionidalways's replacement.
    Mutant("nosessionid", B, 'event["sessionID"] = .string(identifier)', "", mode="stmt", nth=1),
    Mutant("identifierupper", B, "identity.uuid.uuidString.lowercased()", "identity.uuid.uuidString"),
    Mutant("clientuserunhashed", B, "identifier.sha256Hex", "identifier"),
    Mutant("appidempty", B, 'event["appID"] = .string(appID)', 'event["appID"] = .string("")', mode="stmt"),
    Mutant("testmodealwaysfalse", B, 'isTestMode = testMode ? "true" : "false"', 'isTestMode = "false"', mode="stmt"),
    Mutant("testmodeboolean", B, 'event["isTestMode"] = .string(isTestMode)', 'event["isTestMode"] = .boolean(isTestMode == "true")', mode="stmt"),
    Mutant("noreceivedat", B, 'event["receivedAt"] = .string(receivedAt)', "", mode="stmt"),
    Mutant("typeempty", B, 'event["type"] = .string(record.name)', 'event["type"] = .string("")', mode="stmt"),
    Mutant("sdkname", B, '.string("Traffluent")', '.string("")'),
    Mutant("nocontext", B, "event[name] = value", "", mode="stmt"),
    Mutant("hexupper", B, '"0123456789abcdef"', '"0123456789ABCDEF"'),
    Mutant("hexnibbles", B, "text.append(digits[Int(byte >> 4)])\n            text.append(digits[Int(byte & 0x0F)])", "text.append(digits[Int(byte & 0x0F)])\n            text.append(digits[Int(byte >> 4)])", mode="stmt"),

    # The standard context.
    Mutant("noappversion", C, 'parameters["TelemetryDeck.AppInfo.version"] = .string(version)', "", mode="stmt"),
    Mutant("nobuild", C, 'parameters["TelemetryDeck.AppInfo.buildNumber"] = .string(build)', "", mode="stmt"),
    Mutant("versionandbuild", C, '"\\(version) (build \\(build))"', '"\\(version) (\\(build))"'),
    Mutant("nomodel", C, 'parameters["TelemetryDeck.Device.modelName"] = .string(device.model)', "", mode="stmt"),
    Mutant("nooperatingsystem", C, 'parameters["TelemetryDeck.Device.operatingSystem"] = .string(operatingSystem.name)', "", mode="stmt"),
    Mutant("noplatform", C, 'parameters["TelemetryDeck.Device.platform"] = .string(operatingSystem.name)', "", mode="stmt"),
    Mutant("emptyversionsent", C, "!operatingSystem.version.isEmpty", "true"),
    Mutant("systemversionbare", C, '"\\(operatingSystem.name) \\(operatingSystem.version)"', '"\\(operatingSystem.version)"'),
    Mutant("majorwhole", C, "components.prefix(1).joined()", "operatingSystem.version"),
    Mutant("majorminorthree", C, "components.prefix(2)", "components.prefix(3)"),
    Mutant("nolocale", C, 'parameters["TelemetryDeck.RunContext.locale"] = .string(locale.identifier)', "", mode="stmt"),
    Mutant("nolanguage", C, 'parameters["TelemetryDeck.RunContext.language"] = .string(language.identifier)', "", mode="stmt"),
    Mutant("noregion", C, 'parameters["TelemetryDeck.UserPreference.region"] = .string(region.identifier)', "", mode="stmt"),
]
