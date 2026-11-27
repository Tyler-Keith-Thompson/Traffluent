# Planted bugs for GoogleAnalyticsEncoding; run with `just mutate GoogleAnalyticsEncoding`. See
# scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/GoogleAnalyticsEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Mutants are applied in this order, so one whose `old`
# holds another's comes first. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The properties PropertyJSON reads (its PropertyReader), its flattening, its identity and batch
#   splitting: PropertyJSON's spec plants those.
# - The unknownEvent arm of `GoogleAnalyticsEncodingError.init(_ error: PropertyReadingError)`
#   mapped to another case: the catch in json(of:) only reaches it for an event the plan doesn't
#   describe, and the unknownEvent tests pin the case it maps to.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
#   Its instrument is a constant of its own, so HTTPDestinations' `bootstrappedinstrument`
#   reaches it.
# - The endpoint's `?? URL(fileURLWithPath: "/")` fallback and the percent-encoding's `?? self`:
#   neither is ever taken.
# - `#if os(macOS) || os(Linux)` around the factory: a runtime switch can't plant a compile-time
#   condition. GoogleAnalyticsAvailabilityTests (in the simulator) and
#   //Tests/CompileFailures:GoogleAnalyticsFactoryOnServer pin it from both sides.
# - The elements of the reserved event names' set literal: a switch can't sit in a literal; the
#   reservedEventName tests name each kind of entry, the app-stream ones included.
# - The factory's call of refuseApplicationBundle(Bundle.main.bundleURL): no test runs inside an
#   app, so none can see it refuse; the function itself is planted below, through its tests.
# - The notices the encoder's initializer logs for names in the plan: logs are for developers,
#   and tests don't pin them (AGENTS.md, Logging).

TESTS = ["GoogleAnalyticsEncodingTests"]

B = "GoogleAnalyticsBatchEncoder.swift"
N = "String+MeasurementProtocolNames.swift"
U = "UUID+MeasurementProtocol.swift"
F = "HTTPDestination+GoogleAnalytics.swift"

LIMIT = "BatchLimit(maximumRecordCount: 25, maximumByteCount: 100_000, maximumRecordByteCount: 100_000)"

MUTANTS = [
    # The limits.
    Mutant("batchcount26", B, LIMIT, "BatchLimit(maximumRecordCount: 26, maximumByteCount: 100_000, maximumRecordByteCount: 100_000)"),
    Mutant("batchbytes130k", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 130_000, maximumRecordByteCount: 100_000)"),
    Mutant("recordbytes130k", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 100_000, maximumRecordByteCount: 130_000)"),
    Mutant("valuebytesreported", B, "text.utf8.count", "text.count", nth=1),
    Mutant("value101", B, "text.utf8.count > Self.valueByteLimit", "text.utf8.count > 101"),
    Mutant("value99", B, "text.utf8.count > Self.valueByteLimit", "text.utf8.count > 99"),
    Mutant("valueinclusive", B, "text.utf8.count > Self.valueByteLimit", "text.utf8.count >= Self.valueByteLimit"),
    Mutant("valuecharacters", B, "text.utf8.count > Self.valueByteLimit", "text.count > Self.valueByteLimit"),
    Mutant("nocountcheck", B, "parameters.count <= Self.parameterLimit", "true"),
    Mutant("parameters26", B, "parameters.count <= Self.parameterLimit", "parameters.count <= 26"),
    Mutant("parameters24", B, "parameters.count <= Self.parameterLimit", "parameters.count <= 24"),
    Mutant("countexclusive", B, "parameters.count <= Self.parameterLimit", "parameters.count < Self.parameterLimit"),
    Mutant("noearliest", B, "offset < Self.earliestOffset", "false"),
    Mutant("earliest73h", B, "offset < Self.earliestOffset", "offset < -73 * 60 * 60"),
    Mutant("earliest71h", B, "offset < Self.earliestOffset", "offset < -71 * 60 * 60"),
    Mutant("earliestinclusive", B, "offset < Self.earliestOffset", "offset <= Self.earliestOffset"),
    Mutant("nolatest", B, "offset > Self.latestOffset", "false"),
    Mutant("latest16m", B, "offset > Self.latestOffset", "offset > 16 * 60"),
    Mutant("latest14m", B, "offset > Self.latestOffset", "offset > 14 * 60"),
    Mutant("latestinclusive", B, "offset > Self.latestOffset", "offset >= Self.latestOffset"),
    Mutant("windowfromtimestamp", B, "record.timestamp.timeIntervalSince(encodedAt)", "TimeInterval(0)"),
    Mutant("nowperrecord", B, "json(of: record, encodedAt: encodedAt)", "json(of: record, encodedAt: record.timestamp)"),
    # The request's members.
    Mutant("adpersonalizationgranted", B, '.string("DENIED")', '.string("GRANTED")', nth=0),
    Mutant("aduserdatagranted", B, '.string("DENIED")', '.string("GRANTED")', nth=1),
    Mutant("noconsent", B, "Self.consent", "JSON.object([:])"),
    Mutant("clientidrecord", B, "record.pseudonymousIdentity.uuid.measurementProtocolClientID", "record.id.measurementProtocolClientID"),
    Mutant("oneclient", B, "offsets[clientID] = clients.count", "offsets[clientID] = 0", mode="stmt"),
    Mutant("eventnameempty", B, ".string(record.name)", '.string("")'),
    Mutant("noparams", B, ".object(parameters)", ".object([:])"),
    Mutant("timestampmillis", B, ".integer(microseconds)", ".integer(microseconds / 1_000)"),
    Mutant("revealsensitive", B, "reader.properties(of: record, includingSensitiveValues: false)", "reader.properties(of: record, includingSensitiveValues: true)"),
    Mutant("dotseparator", B, 'properties.flattened(separator: "_")', 'properties.flattened(separator: ".")'),
    Mutant("nullskept", B, "$0.value != .null", "true"),
    Mutant("collisionparameterempty", B, ".parameterNameCollision(event: record.name, parameter: error.key)", '.parameterNameCollision(event: record.name, parameter: "")'),
    Mutant("collisionasinvalid", B, ".parameterNameCollision(event: record.name, parameter: error.key)", ".invalidParameterName(event: record.name, parameter: error.key)"),
    Mutant("nosessionid", B, 'parameters["session_id"] = .integer(start)', "_ = start", mode="stmt"),
    Mutant("sessionidseconds", B, ".integer(start)", ".integer(start / 1_000)"),
    # The order of the checks.
    Mutant("readerrorfirst", B, "try record.checkName()", "()", mode="stmt", nth=0),
    Mutant("nonamecheck", B, "try record.checkName()", "()", mode="stmt", nth=1),
    Mutant("unsortednames", B, "parameters.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }", "Array(parameters.keys)"),
    Mutant("descendingnames", B, "$0.utf8.lexicographicallyPrecedes($1.utf8)", "$1.utf8.lexicographicallyPrecedes($0.utf8)"),
    Mutant("noinvalidparameter", B, "names.first(where: { !$0.isMeasurementProtocolName })", "String?.none"),
    Mutant("noreservedparameter", B, "names.first(where: \\.isReservedMeasurementProtocolParameterName)", "String?.none"),
    Mutant("notimestampcheck", B, "record.timestamp.microsecondsSince1970", "Optional(Int64(0))"),
    Mutant("roundedup", B, "(timeIntervalSince1970 * 1_000_000).rounded(.down)", "(timeIntervalSince1970 * 1_000_000).rounded(.up)"),
    Mutant("notrounded", B, "(timeIntervalSince1970 * 1_000_000).rounded(.down)", "timeIntervalSince1970 * 1_000_000"),
    Mutant("noinvalidname", B, "name.isMeasurementProtocolName", "true", nth=2),
    Mutant("noreservedname", B, "!name.isReservedMeasurementProtocolEventName", "true"),
    Mutant("notencodableasunknown", B, "self = .notEncodable(name: name)", "self = .unknownEvent(name: name, version: 0)", mode="stmt"),
    # The names.
    Mutant("name41", N, "utf8.count <= 40", "utf8.count <= 41"),
    Mutant("name39", N, "utf8.count <= 40", "utf8.count <= 39"),
    Mutant("namecharacters", N, "utf8.count <= 40", "count <= 40"),
    Mutant("firstanything", N, "first.isLetter", "true"),
    Mutant("firstdigit", N, "first.isLetter", "first.isLetter || first.isNumber"),
    Mutant("firstascii", N, "first.isLetter", "first.isASCII && first.isLetter", nth=1),
    Mutant("combiningmarks", N, "$0.isLetter", "$0.isLetter || $0.properties.generalCategory == .nonspacingMark"),
    Mutant("restascii", N, "$0.isLetter", "$0.isASCII && $0.isLetter", nth=1),
    Mutant("nonumbers", N, "$0.isNumber", "false"),
    Mutant("nounderscore", N, '$0 == "_"', "false"),
    Mutant("hyphenallowed", N, '$0 == "_"', '$0 == "_" || $0 == "-"'),
    Mutant("decimalonly", N, "$0.isNumber", "$0.properties.generalCategory == .decimalNumber"),
    Mutant("noreservedevents", N, "Self.reservedEventNames.contains(self)", "false"),
    Mutant("reservedcaseless", N, "Self.reservedEventNames.contains(self)", "Self.reservedEventNames.contains(lowercased())"),
    Mutant("nosessionidreserved", N, 'self == "session_id"', "false"),
    Mutant("nofirebaseprefix", N, 'hasPrefix("firebase_")', "false"),
    Mutant("nogaprefix", N, 'hasPrefix("ga_")', "false"),
    Mutant("gaprefixnounderscore", N, 'hasPrefix("ga_")', 'hasPrefix("ga")'),
    Mutant("nogoogleprefix", N, 'hasPrefix("google_")', "false"),
    Mutant("prefixcaseless", N, 'hasPrefix("google_")', 'lowercased().hasPrefix("google_")'),
    # The identifiers.
    Mutant("clientidhex", U, 'return "\\(high).\\(low)"', 'return String(high, radix: 16) + "." + String(low, radix: 16)', mode="stmt"),
    Mutant("clientidswapped", U, 'return "\\(high).\\(low)"', 'return "\\(low).\\(high)"', mode="stmt"),
    Mutant("clientidhighonly", U, 'return "\\(high).\\(low)"', 'return "\\(high).0"', mode="stmt"),
    Mutant("lowfrom7", U, "[bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]", "[bytes.7, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]"),
    Mutant("anyversion", U, "bytes.6 >> 4 == 7", "true"),
    Mutant("anyvariant", U, "bytes.8 >> 6 == 0b10", "true"),
    Mutant("variantbit", U, "bytes.8 >> 6 == 0b10", "bytes.8 >> 7 == 1"),
    Mutant("start40bits", U, "[bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5]", "[bytes.1, bytes.2, bytes.3, bytes.4, bytes.5]"),
    # The factory.
    Mutant("appaccepted", F, "throw .appBundle", "return", mode="stmt"),
    Mutant("appexaccepted", F, '"appex"', '"appex-never"'),
    Mutant("bundlecasesensitive", F, "bundleURL.pathExtension.lowercased()", "bundleURL.pathExtension"),
    Mutant("untrimmedid", F, "measurementID.trimmingCharacters(in: .whitespacesAndNewlines)", "measurementID"),
    Mutant("untrimmedsecret", F, "apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)", "apiSecret"),
    Mutant("emptyidaccepted", F, "!measurementID.isEmpty", "true"),
    Mutant("anyidaccepted", F, "measurementID.isMeasurementID", "true"),
    Mutant("emptysecretaccepted", F, "!apiSecret.isEmpty", "true"),
    Mutant("idprefixcaseless", F, 'hasPrefix("G-")', 'lowercased().hasPrefix("g-")'),
    Mutant("idemptyrest", F, "!rest.isEmpty", "true"),
    Mutant("idnodigits", F, '(UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0)', "false"),
    Mutant("idnoletters", F, '(UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains($0)', "false"),
    Mutant("idatsign", F, 'UInt8(ascii: "A")', 'UInt8(ascii: "@")'),
    Mutant("idbracket", F, 'UInt8(ascii: "Z")', 'UInt8(ascii: "[")'),
    Mutant("idslash", F, 'UInt8(ascii: "0")', 'UInt8(ascii: "/")'),
    Mutant("idcolon", F, 'UInt8(ascii: "9")', 'UInt8(ascii: ":")'),
    Mutant("euglobal", F, '"region1.google-analytics.com"', '"www.google-analytics.com"'),
    Mutant("debugendpoint", F, '"https://\\(host)/mp/collect?\\(query)"', '"https://\\(host)/debug/mp/collect?\\(query)"'),
    Mutant("secretunescaped", F, "apiSecret.percentEncodedForQuery", "apiSecret"),
    Mutant("plusunescaped", F, '"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"', '"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+"'),
    Mutant("nownotpassed", F, "GoogleAnalyticsBatchEncoder(plan: plan, now: now)", "GoogleAnalyticsBatchEncoder(plan: plan)"),
]
