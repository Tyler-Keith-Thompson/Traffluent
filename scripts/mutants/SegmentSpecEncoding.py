# Planted bugs for SegmentSpecEncoding; run with `just mutate SegmentSpecEncoding`. See
# scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/SegmentSpecEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Mutants are applied in this order, so one whose `old`
# holds another's comes first. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The properties PropertyJSON reads (its PropertyReader), its identity, timestamps and batch
#   splitting: PropertyJSON's spec plants those.
# - The unknownEvent arm of `SegmentSpecEncodingError.init(_ error: PropertyReadingError)` mapped
#   to another case: the catch in json(of:) only reaches it for an event the plan doesn't
#   describe, and the unknownEvent tests pin the case it maps to.
# - The factories' `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
# - The endpoints' `?? URL(fileURLWithPath: "/")` fallbacks, and `?? .unlimited` on the limit:
#   the literals always parse, and the limit's numbers are valid.
# - `if let strictMode = HTTPField.Name("X-Strict-Mode")`'s else: the name is a valid token.
# - The notice the encoder's initializer logs for a semantic event name in the plan: logs are for
#   developers, and tests don't pin them (AGENTS.md, Logging).
# - The order `context["ip"]` and the standard context are written in: StandardContext writes no
#   `ip` member.

TESTS = ["SegmentSpecEncodingTests"]

B = "SegmentSpecBatchEncoder.swift"
C = "EventRecord+SegmentSpecContext.swift"
A = "String+BasicAuthorization.swift"
S = "HTTPDestination+Segment.swift"
R = "HTTPDestination+RudderStack.swift"
I = "HTTPDestination+CustomerIO.swift"

MUTANTS = [
    # Each call's members.
    Mutant("typeidentify", B, '.string("track")', '.string("identify")'),
    Mutant("eventnameempty", B, ".string(record.name)", '.string("")'),
    Mutant("nopropertiesobject", B, ".object(properties)", ".object([:])"),
    Mutant("freshmessageid", B, ".string(record.deduplicationID)", ".string(UUID().uuidString.lowercased())"),
    Mutant("anonymousiduppercase", B, "record.pseudonymousIdentity.uuid.uuidString.lowercased()", "record.pseudonymousIdentity.uuid.uuidString"),
    Mutant("anonymousidisrecord", B, "record.pseudonymousIdentity.uuid.uuidString.lowercased()", "record.deduplicationID"),
    Mutant("timestampnow", B, ".string(record.timestamp.iso8601Timestamp)", ".string(Date().iso8601Timestamp)"),
    Mutant("noip", B, 'context["ip"] = .string("0.0.0.0")', "", mode="stmt"),
    Mutant("iplocalhost", B, 'context["ip"] = .string("0.0.0.0")', 'context["ip"] = .string("127.0.0.1")', mode="stmt"),
    # RudderStack's request_ip: written only when the option is on, which only its factory sets.
    Mutant("norequestip", B, 'call["request_ip"] = .string("0.0.0.0")', "", mode="stmt"),
    Mutant("requestiplocalhost", B, 'call["request_ip"] = .string("0.0.0.0")', 'call["request_ip"] = .string("127.0.0.1")', mode="stmt"),
    Mutant("requestipeverywhere", B,
           "self.init(plan: plan, limit: limit, sendsRequestIP: false)",
           "self.init(plan: plan, limit: limit, sendsRequestIP: true)",
           mode="stmt"),
    Mutant("nocontext", B, "record.segmentSpecContext", "[String: JSON]()"),
    Mutant("sensitivewritten", B, "properties = try reader.properties(of: record, includingSensitiveValues: false)", "properties = try reader.properties(of: record, includingSensitiveValues: true)", mode="stmt"),
    # Timestamps.
    Mutant("earlyaccepted", B, "seconds >= Self.earliestSeconds", "true"),
    Mutant("earliestexclusive", B, "seconds >= Self.earliestSeconds", "seconds > Self.earliestSeconds"),
    Mutant("lateaccepted", B, "seconds < Self.endSeconds", "true"),
    Mutant("endinclusive", B, "seconds < Self.endSeconds", "seconds <= Self.endSeconds"),
    Mutant("earliestreform", B, "-62_135_596_800", "-12_212_553_600"),
    # Limits.
    Mutant("countlimit", B, "2_500", "2_501"),
    Mutant("bytelimit", B, "500_000", "512_000"),
    Mutant("recordbytelimit", B, "31_999", "32_000"),
    Mutant("oversizednocount", B, ".oversized(byteCount: byteCount)", ".oversized(byteCount: 0)"),
    # Semantic event names. The catch's guard dropped first, as its statement holds the name check
    # reservedafterreaderror changes.
    Mutant("reservedbeforeunknown", B,
           "if case .unknownEvent = error {} else if record.name.isSemanticEventName {\n                throw .reservedEventName(name: record.name)\n            }",
           "if record.name.isSemanticEventName {\n                throw .reservedEventName(name: record.name)\n            }",
           mode="stmt"),
    Mutant("reservednameaccepted", B, "!record.name.isSemanticEventName", "true"),
    # The second copy is the catch's, after reservedbeforeunknown's: a semantic event the reader
    # can't read.
    Mutant("reservedafterreaderror", B, "record.name.isSemanticEventName", "false", nth=1),
    Mutant("reservedunnamed", B, ".reservedEventName(name: record.name)", '.reservedEventName(name: "")', nth=1),
    Mutant("userdeletedaccepted", B, '"User Deleted"', '"User Removed"'),
    Mutant("devicedeletedaccepted", B, '"Device Deleted"', '"Device Removed"'),
    Mutant("reportdeliveryaccepted", B, '"Report Delivery Event"', '"Report Delivered"'),
    Mutant("unsuppressedaccepted", B, '"User Unsuppressed"', '"User Restored"'),
    Mutant("everynamereserved", B, "Self.semanticEventNames.contains(self)", "true"),
    Mutant("namescaseless", B, "Self.semanticEventNames.contains(self)", "Self.semanticEventNames.contains { $0.lowercased() == lowercased() }"),
    # Context.
    Mutant("noapp", C, 'fields["app"] = .object(app)', "", mode="stmt"),
    Mutant("emptyappkept", C, "!app.isEmpty", "true"),
    Mutant("nobuild", C, "application.build.map(JSON.string)", "Optional<JSON>.none"),
    Mutant("namespaceasversion", C, "application.bundleIdentifier.map(JSON.string)", "application.version.map(JSON.string)"),
    Mutant("noversion", C, "application.version.map(JSON.string)", "Optional<JSON>.none", nth=1),
    Mutant("nomodel", C,
           'fields["device"] = .object(["model": .string(device.model), "type": .string(device.formFactor.segmentDeviceType)])',
           'fields["device"] = .object(["type": .string(device.formFactor.segmentDeviceType)])',
           mode="stmt"),
    Mutant("nodevice", C, 'fields["device"] = .object(["model": .string(device.model), "type": .string(device.formFactor.segmentDeviceType)])', "", mode="stmt"),
    Mutant("nolocale", C, 'fields["locale"] = .string(locale.identifier(.bcp47))', "", mode="stmt"),
    Mutant("localeicu", C, "locale.identifier(.bcp47)", "locale.identifier"),
    Mutant("nonetwork", C, 'fields["network"] = .object(["cellular": .boolean(network == .cellular), "wifi": .boolean(network == .wifi)])', "", mode="stmt"),
    Mutant("wifialways", C, "network == .wifi", "true"),
    Mutant("cellularaswifi", C, "network == .cellular", "network == .wifi"),
    Mutant("noos", C, 'fields["os"] = .object(["name": .string(operatingSystem.name), "version": .string(operatingSystem.version)])', "", mode="stmt"),
    Mutant("osnameasversion", C, ".string(operatingSystem.name)", ".string(operatingSystem.version)"),
    Mutant("padasmacos", C, '"ios"', '"macos"'),
    Mutant("macasios", C, '"macos"', '"ios"', nth=1),
    Mutant("tvasios", C, '"tvos"', '"ios"'),
    Mutant("watchasios", C, '"watchos"', '"ios"'),
    Mutant("visionasios", C, '"visionos"', '"ios"'),
    # Basic authorization.
    Mutant("basicnocolon", A, '(self + ":")', "self"),
    Mutant("basicpassword", A, '(self + ":")', '(":" + self)'),
    Mutant("bearernotbasic", A, '"Basic "', '"Bearer "'),
    # Segment's factory.
    Mutant("segmentuntrimmed", S, "writeKey.trimmingCharacters(in: .whitespacesAndNewlines)", "writeKey"),
    Mutant("segmentemptyaccepted", S, "!writeKey.isEmpty", "true"),
    Mutant("segmentnoauthorization", S, "[.authorization: writeKey.basicAuthorization]", "[:]"),
    Mutant("segmenteuasus", S, '"https://events.eu1.segmentapis.com/v1/batch"', '"https://api.segment.io/v1/batch"'),
    Mutant("segmentusaseu", S, '"https://api.segment.io/v1/batch"', '"https://events.eu1.segmentapis.com/v1/batch"', nth=0),
    Mutant("segmenttracing", S, "NoOpInstrument()", "InstrumentationSystem.instrument"),
    # RudderStack's factory.
    Mutant("rudderuntrimmed", R, "writeKey.trimmingCharacters(in: .whitespacesAndNewlines)", "writeKey"),
    Mutant("rudderemptyaccepted", R, "!writeKey.isEmpty", "true"),
    Mutant("ruddernoauthorization", R, "[.authorization: writeKey.basicAuthorization]", "[:]"),
    Mutant("ruddertracing", R, "NoOpInstrument()", "InstrumentationSystem.instrument"),
    Mutant("rudderhttpaccepted", R, 'components.scheme?.lowercased() == "https"', "true"),
    Mutant("rudderschemecase", R, 'components.scheme?.lowercased() == "https"', 'components.scheme == "https"'),
    Mutant("ruddernohost", R, "components.percentEncodedHost?.isEmpty == false", "true"),
    Mutant("rudderuseraccepted", R, "components.percentEncodedUser == nil", "true"),
    Mutant("rudderqueryaccepted", R, "components.percentEncodedQuery == nil", "true"),
    Mutant("rudderfragmentaccepted", R, "components.percentEncodedFragment == nil", "true"),
    Mutant("rudderslashkept", R, "path.removeLast()", "break", mode="stmt"),
    Mutant("rudderv1accepted", R, 'last != "v1"', "true"),
    Mutant("rudderbatchaccepted", R, 'last != "batch"', "true"),
    Mutant("rudderwrongpath", R, 'path + "/v1/batch"', 'path + "/v1/track"'),
    Mutant("rudderpathdropped", R, 'path + "/v1/batch"', '"/v1/batch"'),
    Mutant("ruddercasesensitive", R, 'path.split(separator: "/").last?.lowercased()', 'path.split(separator: "/").last.map(String.init)'),
    Mutant("rudderrequestipoff", R, "SegmentSpecBatchEncoder(plan: plan, sendsRequestIP: true)", "SegmentSpecBatchEncoder(plan: plan)"),
    # Customer.io's factory.
    Mutant("ciountrimmed", I, "apiKey.trimmingCharacters(in: .whitespacesAndNewlines)", "apiKey"),
    Mutant("cioemptyaccepted", I, "!apiKey.isEmpty", "true"),
    Mutant("cioprivateaccepted", I, '!apiKey.hasPrefix("sk_")', "true"),
    Mutant("cioprivatecase", I, '!apiKey.hasPrefix("sk_")', '!apiKey.lowercased().hasPrefix("sk_")'),
    Mutant("cioregionmismatchaccepted", I, "keyRegion != region", "false"),
    Mutant("cioeukeyasus", I, '"pk_eu_"', '"pk_us_"'),
    Mutant("ciouskeyaseu", I, '"pk_us_"', '"pk_eu_"', nth=0),
    Mutant("ciobasic", I, '"Bearer \\(apiKey)"', "apiKey.basicAuthorization"),
    Mutant("ciononstrict", I, 'headerFields[strictMode] = "1"', "", mode="stmt"),
    Mutant("ciostrictzero", I, '"1"', '"0"'),
    Mutant("ciotracing", I, "NoOpInstrument()", "InstrumentationSystem.instrument"),
    Mutant("cioeuasus", I, '"https://cdp-eu.customer.io/v1/batch"', '"https://cdp.customer.io/v1/batch"'),
    Mutant("ciousaseu", I, '"https://cdp.customer.io/v1/batch"', '"https://cdp-eu.customer.io/v1/batch"', nth=0),
]
