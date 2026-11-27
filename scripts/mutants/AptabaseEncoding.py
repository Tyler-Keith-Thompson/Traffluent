# Planted bugs for AptabaseEncoding; run with `just mutate AptabaseEncoding`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/AptabaseEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Mutants are applied in this order, so one whose `old` holds another's
# comes first. Every mutant must be caught; one that survives needs a test, or a note here saying
# why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The properties PropertyJSON reads (its PropertyReader), flattening, identity, batch splitting
#   and request deadlines: PropertyJSON's spec plants those.
# - The unknownEvent arm of `AptabaseEncodingError.init(_ error: PropertyReadingError)` mapped to
#   another case: the catch in json(of:) only reaches it for an event the plan doesn't describe,
#   and the unknownEvent tests pin the case it maps to.
# - The catch of iso8601Timestamp: the guard before it already refuses every timestamp the
#   conversion would, so it is never taken.
# - The catch in requests(for:), which falls back to no deadline: BatchLimit only throws for a
#   maximum age that isn't positive, and the window is 23 hours.
# - The endpoints' `?? URL(fileURLWithPath: "/")` fallbacks, and `guard let endpoint =
#   components.url`: the literals always parse, and so do components made from a URL.
# - DEV left out of `case "SH", "DEV"`: a mutant switch can't hold a case pattern. The setup
#   error tests make a DEV key without a host throw selfHostedAppKeyWithoutHost, and the
#   conformance tests post a DEV key to its host, which pins it.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument.
# - The notices the encoder's initializer logs for names Aptabase refuses, and the once-per-member
#   notice for a system property left out (NoticedSystemProperties): logs are for developers, and
#   tests don't pin them (AGENTS.md, Logging).

TESTS = ["AptabaseEncodingTests"]

B = "AptabaseBatchEncoder.swift"
F = "HTTPDestination+Aptabase.swift"
N = "String+AptabaseNames.swift"
R = "AptabaseRegion.swift"
S = "EventRecord+AptabaseSystemProperties.swift"

LIMIT = "BatchLimit(maximumRecordCount: 25, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"
NAME_CHECK_ON_FAILURE = "if case .unknownEvent = error {} else {\n                try record.checkAptabaseName()\n            }"

MUTANTS = [
    # The limits.
    Mutant("batchcount26", B, LIMIT, "BatchLimit(maximumRecordCount: 26, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchcount24", B, LIMIT, "BatchLimit(maximumRecordCount: 24, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchbytes1000001", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 1_000_001, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchbytes999999", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 999_999, maximumRecordByteCount: 1_000_000)"),
    Mutant("oversizedbytecount", B, ".oversized(byteCount: byteCount)", "AptabaseEncodingError.oversized(byteCount: 0)"),
    Mutant("limitignored", B, "self.limit = limit", "self.limit = AptabaseBatchEncoder.batchLimit", mode="stmt"),
    Mutant("nodeadline", B, "return try limit.requests(for: batch, in: .array, maximumAge: Self.window, encoding: encoding, oversized: oversized)", "return limit.requests(for: batch, in: .array, encoding: encoding, oversized: oversized)", mode="stmt"),
    Mutant("window24h", B, "23 * 60 * 60", "24 * 60 * 60"),

    # The key and the host.
    Mutant("untrimmedkey", F, "appKey.trimmingCharacters(in: .whitespacesAndNewlines)", "appKey"),
    Mutant("emptykey", R, "!appKey.isEmpty", "true"),
    Mutant("partcount4", R, "parts.count == 3", "parts.count >= 3"),
    Mutant("anyprefix", R, 'parts[0] == "A"', "true"),
    Mutant("emptybody", R, "!parts[2].isEmpty", "true"),
    Mutant("anybody", R, "parts[2].utf8.allSatisfy(\\.isASCIILetterOrDigit)", "true"),
    Mutant("nodigits", R, '(UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(self)', "false"),
    Mutant("nouppercase", R, '(UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(self)', "false"),
    Mutant("nolowercase", R, '(UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(self)', "false"),
    Mutant("digitsfrom1", R, 'UInt8(ascii: "0")', 'UInt8(ascii: "1")'),
    Mutant("digitsto8", R, 'UInt8(ascii: "9")', 'UInt8(ascii: "8")'),
    Mutant("upperfromB", R, 'UInt8(ascii: "A")', 'UInt8(ascii: "B")'),
    Mutant("uppertoY", R, 'UInt8(ascii: "Z")', 'UInt8(ascii: "Y")'),
    Mutant("lowerfromb", R, 'UInt8(ascii: "a")', 'UInt8(ascii: "b")'),
    Mutant("lowertoy", R, 'UInt8(ascii: "z")', 'UInt8(ascii: "y")'),
    Mutant("regioncaseless", R, 'parts[1]', 'Substring(parts[1].uppercased())'),
    Mutant("euisus", R, 'self = .eu', 'self = .us', mode="stmt"),
    Mutant("unknownisselfhosted", R, 'throw .unknownRegion', 'self = .selfHosted', mode="stmt"),
    Mutant("cloudhostallowed", F, 'throw .cloudAppKeyWithHost', 'endpoint = try host?.aptabaseEndpoint ?? AptabaseRegion.euEndpoint', mode="stmt"),
    Mutant("euendpoint", F, '"https://eu.aptabase.com/api/v0/events"', '"https://aptabase.com/api/v0/events"'),
    Mutant("usendpoint", F, '"https://us.aptabase.com/api/v0/events"', '"https://us.aptabase.com/api/v0/event"'),
    Mutant("httpallowed", F, 'components.scheme?.lowercased() == "https"', 'components.scheme?.lowercased().hasPrefix("http") == true'),
    Mutant("schemecased", F, 'components.scheme?.lowercased() == "https"', 'components.scheme == "https"'),
    Mutant("nohost", F, "components.percentEncodedHost?.isEmpty == false", "true"),
    Mutant("useradmitted", F, "components.percentEncodedUser == nil", "true"),
    Mutant("queryadmitted", F, "components.percentEncodedQuery == nil", "true"),
    Mutant("fragmentadmitted", F, "components.percentEncodedFragment == nil", "true"),
    Mutant("slasheskept", F, "path.removeLast()", "break", mode="stmt"),
    Mutant("eventsendpointadmitted", F, '!lowercased.hasSuffix("/api/v0/events")', "true"),
    Mutant("eventendpointadmitted", F, '!lowercased.hasSuffix("/api/v0/event")', "true"),
    Mutant("endpointcased", F, "path.lowercased()", "path"),
    Mutant("endpointsingle", F, 'components.percentEncodedPath = path + "/api/v0/events"', 'components.percentEncodedPath = path + "/api/v0/event"', mode="stmt"),
    Mutant("appkeyname", F, 'HTTPField.Name("App-Key")', 'HTTPField.Name("X-App-Key")'),
    Mutant("nokeyheader", F, "headerFields[name] = appKey", "", mode="stmt"),
    Mutant("bootstrappedinstrument", F, "NoOpInstrument()", "InstrumentationSystem.instrument"),
    Mutant("factorydebug", F, "AptabaseBatchEncoder(isDebug: isDebug, plan: plan, now: now)", "AptabaseBatchEncoder(isDebug: false, plan: plan, now: now)"),
    Mutant("factoryclock", F, "AptabaseBatchEncoder(isDebug: isDebug, plan: plan, now: now)", "AptabaseBatchEncoder(isDebug: isDebug, plan: plan)"),

    # The name and length rules.
    Mutant("eventname59", N, "utf16.count <= 60", "utf16.count < 60"),
    Mutant("eventname61", N, "utf16.count <= 60", "utf16.count <= 61"),
    Mutant("eventnamescalars", N, "utf16.count <= 60", "unicodeScalars.count <= 60"),
    Mutant("blankeventname", N, '!isBlank', 'true'),
    Mutant("blankanyspace", N, "unicodeScalars.allSatisfy(\\.properties.isWhitespace)", "unicodeScalars.allSatisfy { $0 == \" \" }"),
    Mutant("blankonespace", N, "unicodeScalars.allSatisfy(\\.properties.isWhitespace)", "unicodeScalars.contains(where: \\.properties.isWhitespace)"),
    Mutant("propertyname39", N, "utf16.count <= 40", "utf16.count < 40"),
    Mutant("propertyname41", N, "utf16.count <= 40", "utf16.count <= 41"),
    Mutant("propertynamescalars", N, "utf16.count <= 40", "unicodeScalars.count <= 40"),
    Mutant("value179", N, "utf16.count <= 180", "utf16.count < 180"),
    Mutant("value181", N, "utf16.count <= 180", "utf16.count <= 181"),
    Mutant("valuescalars", N, "utf16.count <= 180", "unicodeScalars.count <= 180"),

    # The skipped records and their order.
    # The second occurrence, after a record is read; the first is in the reader's catch.
    Mutant("namenotchecked", B, "try record.checkAptabaseName()", "", mode="stmt", nth=1),
    Mutant("namecheckedwhenunknown", B, NAME_CHECK_ON_FAILURE, "try record.checkAptabaseName()", mode="stmt"),
    Mutant("namenotcheckedonfailure", B, NAME_CHECK_ON_FAILURE, "", mode="stmt"),
    # The second occurrence, in checkAptabaseName: the first is the initializer's notice.
    Mutant("invalideventname", B, "name.isAptabaseEventName", "true", nth=1),
    Mutant("collisionkey", B, "error.key", '""'),
    Mutant("descendingnames", B, "properties.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }", "properties.keys.sorted { $1.utf8.lexicographicallyPrecedes($0.utf8) }"),
    Mutant("noblankname", B, "names.first(where: \\.isBlank)", "nil"),
    Mutant("nolongname", B, "names.first(where: { !$0.fitsAptabasePropertyName })", "nil"),
    Mutant("nolongvalue", B, "!value.fitsAptabasePropertyValue", "false"),
    Mutant("valuepropertyname", B, "throw .propertyValueTooLong(event: record.name, property: name, length: value.utf16.count)", 'throw .propertyValueTooLong(event: record.name, property: "", length: value.utf16.count)', mode="stmt"),
    # The second occurrence, the original; the first is valuepropertyname's replacement.
    Mutant("valuelengthcharacters", B, "value.utf16.count", "value.count", nth=1),
    Mutant("nonumberrange", B, "!(value.magnitude < Self.decimalBound)", "false"),
    Mutant("numberrangeinclusive", B, "!(value.magnitude < Self.decimalBound)", "!(value.magnitude <= Self.decimalBound)"),
    Mutant("numbersigned", B, "!(value.magnitude < Self.decimalBound)", "!(value < Self.decimalBound)"),
    Mutant("decimalbound2to95", B, "79_228_162_514_264_337_593_543_950_336", "39_614_081_257_132_168_796_771_975_168"),
    Mutant("nosystemlength", B, "value.utf16.count > maximum", "false"),
    Mutant("systemlengthinclusive", B, "value.utf16.count > maximum", "value.utf16.count >= maximum"),
    Mutant("systemlengthcharacters", B, "value.utf16.count > maximum", "value.count > maximum"),
    Mutant("systemmemberkept", B, "return false", "return true", mode="stmt"),
    Mutant("osname31", B, '["osName": 30, "osVersion": 100, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 100]', '["osName": 31, "osVersion": 100, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 100]'),
    Mutant("osversion99", B, '["osName": 30, "osVersion": 100, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 100]', '["osName": 30, "osVersion": 99, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 100]'),
    Mutant("appversion51", B, '["osName": 30, "osVersion": 100, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 100]', '["osName": 30, "osVersion": 100, "appVersion": 51, "appBuildNumber": 20, "deviceModel": 100]'),
    Mutant("appbuild19", B, '["osName": 30, "osVersion": 100, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 100]', '["osName": 30, "osVersion": 100, "appVersion": 50, "appBuildNumber": 19, "deviceModel": 100]'),
    Mutant("devicemodel101", B, '["osName": 30, "osVersion": 100, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 100]', '["osName": 30, "osVersion": 100, "appVersion": 50, "appBuildNumber": 20, "deviceModel": 101]'),
    Mutant("noearliest", B, "seconds >= Self.earliestSeconds", "true"),
    Mutant("noend", B, "seconds < Self.endSeconds", "true"),
    Mutant("earliestexclusive", B, "seconds >= Self.earliestSeconds", "seconds > Self.earliestSeconds"),
    Mutant("endinclusive", B, "seconds < Self.endSeconds", "seconds <= Self.endSeconds"),
    Mutant("nonfiniteclock", B, "offset.isFinite", "true"),
    Mutant("nowindow", B, "offset >= -Self.windowSeconds", "true"),
    Mutant("windowexclusive", B, "offset >= -Self.windowSeconds", "offset > -Self.windowSeconds"),
    Mutant("windowbothsides", B, "offset >= -Self.windowSeconds", "offset.magnitude <= Self.windowSeconds"),
    Mutant("sensitivesent", B, "read = try reader.properties(of: record, includingSensitiveValues: false)", "read = try reader.properties(of: record, includingSensitiveValues: record.revealsSensitiveValues)", mode="stmt"),

    # The event's members and values.
    Mutant("nullssent", B, 'read.flattened(separator: ".").filter { $0.value != .null }', 'read.flattened(separator: ".")'),
    # The second occurrence, the original; the first is nullssent's replacement.
    Mutant("underscoreseparator", B, 'read.flattened(separator: ".")', 'read.flattened(separator: "_")', nth=1),
    Mutant("emptypropertiessent", B, "!properties.isEmpty", "true"),
    Mutant("nopropertiessent", B, 'event["props"] = .object(properties)', "", mode="stmt"),
    Mutant("eventempty", B, '.string(record.name)', '.string("")'),
    Mutant("sessionrecord", B, "record.pseudonymousIdentity.uuid.uuidString.lowercased()", "record.id.uuidString.lowercased()"),
    Mutant("sessionupper", B, "record.pseudonymousIdentity.uuid.uuidString.lowercased()", "record.pseudonymousIdentity.uuid.uuidString"),
    Mutant("timestampepoch", B, '.string(timestamp)', '.string(String(record.timestamp.timeIntervalSince1970))'),
    Mutant("debugfalse", B, 'systemProperties["isDebug"] = .boolean(isDebug)', 'systemProperties["isDebug"] = .boolean(false)', mode="stmt"),
    Mutant("debugstring", B, 'systemProperties["isDebug"] = .boolean(isDebug)', 'systemProperties["isDebug"] = .string(String(isDebug))', mode="stmt"),
    Mutant("nosdkversion", B, 'systemProperties["sdkVersion"] = .string(Self.sdkVersion)', "", mode="stmt"),
    Mutant("nosystemcontext", B, "system.mapValues(JSON.string)", "[String: JSON]()"),

    # The system properties from the standard context.
    Mutant("noosname", S, 'members["osName"] = operatingSystem.name', "", mode="stmt"),
    Mutant("noosversion", S, 'members["osVersion"] = operatingSystem.version', "", mode="stmt"),
    Mutant("noappversion", S, 'members["appVersion"] = application.version', "", mode="stmt"),
    Mutant("noappbuild", S, 'members["appBuildNumber"] = application.build', "", mode="stmt"),
    Mutant("nodevicemodel", S, 'members["deviceModel"] = device.model', "", mode="stmt"),
    Mutant("nolocale", S, 'members["locale"] = locale', "", mode="stmt"),
    Mutant("localeunderscore", S, '"\\(language)-\\(region)"', '"\\(language)_\\(region)"'),
    Mutant("localelanguageonly", S, 'tagged.utf16.count <= 10', 'false'),
    Mutant("localetaglength9", S, "tagged.utf16.count <= 10", "tagged.utf16.count < 10"),
    Mutant("localeidentifier", S, "language.languageCode?.identifier", "Optional(identifier)"),
]
