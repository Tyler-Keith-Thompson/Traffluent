# Planted bugs for SnowplowEncoding; run with `just mutate SnowplowEncoding`. See
# scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/SnowplowEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Mutants are applied in this order, so one whose `old`
# holds another's comes first. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The properties PropertyJSON reads (its PropertyReader), its identity and batch splitting:
#   PropertyJSON's spec plants those. The Iglu name rules and SchemaVer mapping are TrackingPlans'
#   (String+IgluNames.swift), planted in its spec.
# - The unknownEvent arm of `SnowplowEncodingError.init(_ error: PropertyReadingError)` mapped to
#   another case: the catch in json(of:) only reaches it for an event the plan doesn't describe,
#   and the unknownEvent tests pin the case it maps to.
# - The catch of millisecondsSince1970(): the guard before it already refuses every timestamp the
#   conversion would, so it is never taken.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
#   Its instrument is a constant of its own, so HTTPDestinations' `bootstrappedinstrument`
#   reaches it.
# - The `if let HTTPField.Name("SP-Anonymous")` and `guard let endpoint = components.url` else
#   arms: neither is ever taken for a valid field name and a URL that URLComponents read.
# - The `.wiredEthernet, .other` arm of snowplowNetworkType: the test of a wired and an other
#   network pins that neither is sent, and nil is the only value the schema's enum lacks.
# - Mutants that only a case pattern, a guard's list of conditions or a dictionary entry could hold,
#   which mutate.py's expression and statement switches can't: an unknownEvent reported after an
#   invalid name (pinned by "unknownEvent even when Iglu doesn't take its name"), an `stm` member
#   added, the wired and other networks given a value, a single form factor's platform moved, and
#   the collector check run after the encoder's. Their tests are listed by name in the suites.
# - The notices the encoder's initializer logs for events Iglu can't name: logs are for
#   developers, and tests don't pin them (AGENTS.md, Logging).

TESTS = ["SnowplowEncodingTests"]

B = "SnowplowBatchEncoder.swift"
C = "EventRecord+SnowplowContext.swift"
F = "HTTPDestination+Snowplow.swift"

LIMIT = "BatchLimit(maximumRecordCount: 25, maximumByteCount: 40_000, maximumRecordByteCount: 150_000, sendsLargeRecordsAlone: true)"

MUTANTS = [
    # The limits.
    Mutant("batchcount26", B, LIMIT, "BatchLimit(maximumRecordCount: 26, maximumByteCount: 40_000, maximumRecordByteCount: 150_000, sendsLargeRecordsAlone: true)"),
    Mutant("batchbytes60k", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 60_000, maximumRecordByteCount: 150_000, sendsLargeRecordsAlone: true)"),
    Mutant("batchbytes39999", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 39_999, maximumRecordByteCount: 150_000, sendsLargeRecordsAlone: true)"),
    Mutant("recordbytes150001", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 40_000, maximumRecordByteCount: 150_001, sendsLargeRecordsAlone: true)"),
    Mutant("recordbytes149999", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 40_000, maximumRecordByteCount: 149_999, sendsLargeRecordsAlone: true)"),
    Mutant("largeeventsskipped", B, LIMIT, "BatchLimit(maximumRecordCount: 25, maximumByteCount: 40_000, maximumRecordByteCount: 150_000)"),
    Mutant("oversizedbytecount", B, ".oversized(byteCount: byteCount)", "SnowplowEncodingError.oversized(byteCount: 0)"),

    # The setup checks.
    Mutant("anyvendor", B, "guard vendor.isIgluVendor else { throw .invalidVendor }", "", mode="stmt"),
    Mutant("emptyappid", B, "!appID.isEmpty", "true"),
    Mutant("anyappidlength", B, "appID.utf16.count <= 255", "true"),
    Mutant("appid256", B, "appID.utf16.count <= 255", "appID.utf16.count <= 256"),
    Mutant("appid254", B, "appID.utf16.count <= 255", "appID.utf16.count <= 254"),
    Mutant("appidcharacters", B, "appID.utf16.count <= 255", "appID.count <= 255"),
    Mutant("anyschemakey", B, "schema.name.hasIgluSchemaKey(version: schema.version)", "true"),

    # The skipped records and their order.
    Mutant("invalidnameread", B, "schemaURI == nil", "false"),
    Mutant("noearliest", B, "seconds >= Self.earliestSeconds", "true"),
    Mutant("noend", B, "seconds < Self.endSeconds", "true"),
    Mutant("earliestexclusive", B, "seconds >= Self.earliestSeconds", "seconds > Self.earliestSeconds"),
    Mutant("endinclusive", B, "seconds < Self.endSeconds", "seconds <= Self.endSeconds"),
    Mutant("earliestyear1", B, "-62_167_219_200", "-62_135_596_800"),
    Mutant("endyear9999", B, "253_402_300_800", "253_370_764_800"),

    # The event's members.
    Mutant("envelopeschema", B, '"iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4"', '"iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-3"'),
    Mutant("unstructschema", B, '"iglu:com.snowplowanalytics.snowplow/unstruct_event/jsonschema/1-0-0"', '"iglu:com.snowplowanalytics.snowplow/unstruct_event/jsonschema/1-0-1"'),
    Mutant("contextsschema", B, '"iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-1"', '"iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-0"'),
    Mutant("eventnotselfdescribing", B, ".selfDescribing(schemaURI, data: .object(properties))", "JSON.object(properties)"),
    Mutant("aidempty", B, ".string(appID)", '.string("")'),
    Mutant("dtmseconds", B, ".string(String(milliseconds))", ".string(String(milliseconds / 1000))", nth=0),
    Mutant("ttmseconds", B, ".string(String(milliseconds))", ".string(String(milliseconds / 1000))", nth=1),
    Mutant("eventtype", B, '.string("ue")', '.string("se")'),
    Mutant("eidupper", B, ".string(record.deduplicationID)", ".string(record.id.uuidString)"),
    Mutant("ipempty", B, '.string("0.0.0.0")', '.string("")'),
    Mutant("noplatform", B, ".string(record.snowplowPlatform)", '.string("app")'),
    Mutant("trackerempty", B, '.string("traffluent")', '.string("")'),
    Mutant("uepxbase64", B, ".string(event.minified)", ".string(Data(event.minified.utf8).base64EncodedString())"),
    Mutant("duidinsteadofsid", B, 'payload["sid"] = .string(session.uuidString.lowercased())', 'payload["duid"] = .string(session.uuidString.lowercased())', mode="stmt"),
    Mutant("nosid", B, 'payload["sid"] = .string(session.uuidString.lowercased())', "", mode="stmt"),
    Mutant("sidupper", B, 'payload["sid"] = .string(session.uuidString.lowercased())', 'payload["sid"] = .string(session.uuidString)', mode="stmt"),
    Mutant("noentities", B, "!entities.isEmpty", "false"),
    Mutant("emptyco", B, "!entities.isEmpty", "true"),
    Mutant("sensitivesent", B, "properties = try reader.properties(of: record, includingSensitiveValues: false)", "properties = try reader.properties(of: record, includingSensitiveValues: record.revealsSensitiveValues)", mode="stmt"),

    # The platform and the entities.
    Mutant("macweb", C, 'return "pc"', 'return "web"', mode="stmt"),
    Mutant("mobsrv", C, 'return "mob"', 'return "srv"', mode="stmt"),
    Mutant("tvcnsl", C, 'return "tv"', 'return "cnsl"', mode="stmt"),
    Mutant("nodeviceiot", C, 'return "app"', 'return "iot"', mode="stmt"),
    Mutant("mobilewithoutsystem", C, "context[OperatingSystemKey.self]", 'Optional(context[OperatingSystemKey.self] ?? OperatingSystemKey.Value(name: "iOS", version: "0"))'),
    Mutant("manufacturer", C, '.string("Apple Inc.")', '.string("Apple")'),
    Mutant("nonetwork", C, 'mobile["networkType"] = .string(networkType)', "", mode="stmt"),
    Mutant("nolanguage", C, 'mobile["language"] = .string(language)', "", mode="stmt"),
    Mutant("anylanguagelength", C, "language.utf16.count <= 8", "true"),
    Mutant("languageidentifier", C, "context[LocaleKey.self]?.language.languageCode?.identifier", "context[LocaleKey.self]?.identifier"),
    Mutant("mobileschema", C, '"iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-3"', '"iglu:com.snowplowanalytics.snowplow/mobile_context/jsonschema/1-0-2"'),
    Mutant("applicationwithoutbuild", C, "application.build", 'Optional(application.build ?? "")'),
    Mutant("anyversionlength", C, "version.utf16.count <= 255", "true"),
    Mutant("anybuildlength", C, "build.utf16.count <= 255", "true"),
    Mutant("build256", C, "build.utf16.count <= 255", "build.utf16.count <= 256"),
    Mutant("applicationschema", C, '"iglu:com.snowplowanalytics.mobile/application/jsonschema/1-0-0"', '"iglu:com.snowplowanalytics.snowplow/application/jsonschema/1-0-0"'),
    Mutant("ostypeios", C, '"ios"', '"iOS"'),
    Mutant("ostypetvos", C, '"tvos"', '"tvOS"'),
    Mutant("ostypewatchos", C, '"watchos"', '"watchOS"'),
    Mutant("ostypevisionos", C, '"visionos"', '"visionOS"'),
    Mutant("ostypemacos", C, '"osx"', '"macos"'),
    Mutant("ostypeother", C, "name.lowercased()", "name"),
    Mutant("networkcellular", C, '"mobile"', '"cellular"'),
    Mutant("networkwifi", C, '"wifi"', '"mobile"'),
    Mutant("networkoffline", C, '"offline"', "String?.none"),

    # The factory and its endpoint.
    Mutant("noanonymous", F, 'headerFields[anonymous] = "*"', "", mode="stmt"),
    Mutant("anonymousvalue", F, 'headerFields[anonymous] = "*"', 'headerFields[anonymous] = "1"', mode="stmt"),
    Mutant("httpallowed", F, 'components.scheme?.lowercased() == "https"', 'components.scheme?.lowercased().hasPrefix("http") == true'),
    Mutant("schemecase", F, 'components.scheme?.lowercased() == "https"', 'components.scheme == "https"'),
    Mutant("nohost", F, "components.percentEncodedHost?.isEmpty == false", "true"),
    Mutant("userallowed", F, "components.percentEncodedUser == nil", "true"),
    Mutant("queryallowed", F, "components.percentEncodedQuery == nil", "true"),
    Mutant("fragmentallowed", F, "components.percentEncodedFragment == nil", "true"),
    Mutant("trailingslash", F, "path.removeLast()", "break", mode="stmt"),
    Mutant("tp2allowed", F, 'last != "tp2"', "true"),
    Mutant("vendorpathallowed", F, 'last != "com.snowplowanalytics.snowplow"', "true"),
    Mutant("lastcase", F, 'path.split(separator: "/").last?.lowercased()', 'path.split(separator: "/").last.map(String.init)'),
    Mutant("decodedpath", F, "components.percentEncodedPath", "components.path", nth=0),
    Mutant("endpointpath", F, 'path + "/com.snowplowanalytics.snowplow/tp2"', 'path + "/com.snowplowanalytics.snowplow/tp1"'),
]
