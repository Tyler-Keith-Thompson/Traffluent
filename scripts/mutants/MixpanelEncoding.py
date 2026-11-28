# Planted bugs for MixpanelEncoding; run with `just mutate MixpanelEncoding`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/MixpanelEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Mutants are applied in this order, so one whose `old`
# holds another's comes first. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The properties PropertyJSON reads (its PropertyReader), its identity, timestamps and batch
#   splitting: PropertyJSON's spec plants those.
# - The unknownEvent arm of `MixpanelEncodingError.init(_ error: PropertyReadingError)` mapped to
#   another case: the catch in json(of:) only reaches it for an event the plan doesn't describe,
#   and the unknownEvent tests pin the case it maps to.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
#   Its instrument is a constant of its own, so `bootstrappedinstrument` reaches it.
# - The URLSessionTransport factory's `now:` argument, passed on to the other factory: a mutant
#   switch can't hold an argument, and no test sends through URLSession.
# - The past side of the window written as `offset.magnitude <= Self.windowSeconds`: the
#   future side's hour already refuses every offset past 119 hours ahead.
# - An `offset.isFinite` term in the window's guard, or one dropped: the two bounds already refuse
#   NaN, which compares false, and each infinity, which falls outside one of them. The non-finite
#   clock tests pin the outcome.
# - The catch in requests(for:), which falls back to no deadline: BatchLimit only throws for a
#   maximum age below zero, and the window is 119 hours.
# - The endpoints' `?? URL(fileURLWithPath: "/")` fallbacks: the literals always parse.
# - A timestamp with no epoch-milliseconds form taken as 0 rather than thrown at: 0 is before
#   1971, so the guard after it throws the same error.
# - The order the context and the identity are written in: no context key shares a name with a
#   member the encoder writes, so either order writes the same object.
# - The notice the encoder's initializer logs for a reserved property in the plan: logs are for
#   developers, and tests don't pin them (AGENTS.md, Logging).

TESTS = ["MixpanelEncodingTests"]

B = "MixpanelBatchEncoder.swift"
C = "EventRecord+MixpanelContext.swift"
F = "HTTPDestination+Mixpanel.swift"

MUTANTS = [
    # Each event's members.
    Mutant("eventnameempty", B, ".string(record.name)", '.string("")'),
    Mutant("nopropertiesobject", B, ".object(properties)", ".object([:])"),
    Mutant("freshinsertid", B, ".string(record.deduplicationID)", ".string(UUID().uuidString.lowercased())"),
    Mutant("timeinseconds", B, ".integer(time)", ".integer(time / 1_000)"),
    # The window checked before the 1971 guard (TRAF-135), so a record of 1960 under a clock of
    # 2026 would be reported as outside the window rather than unrepresentable. Before the 1971
    # and window mutants, as its statement holds their text; they take the original's copy, the
    # second (nth=1), after the one its new branch writes.
    Mutant("windowbeforeearliest", B,
           "guard time >= Self.earliestTime else {\n            throw .unrepresentableTimestamp\n        }",
           "guard offset >= -Self.windowSeconds, offset <= Self.latestOffset else {\n            throw .timestampOutsideWindow\n        }\n        guard time >= Self.earliestTime else {\n            throw .unrepresentableTimestamp\n        }",
           mode="stmt"),
    Mutant("before1971accepted", B, "time >= Self.earliestTime", "true", nth=1),
    Mutant("earliestexclusive", B, "time >= Self.earliestTime", "time > Self.earliestTime", nth=1),
    Mutant("earliestinseconds", B, "31_536_000_000", "31_536_000"),
    Mutant("notoken", B, 'properties["token"] = .string(projectToken)', "", mode="stmt"),
    Mutant("tokenempty", B, ".string(projectToken)", '.string("")'),
    Mutant("noip", B, 'properties["ip"] = .string("0")', "", mode="stmt"),
    Mutant("ipone", B, '.string("0")', '.string("1")'),
    # Identity: the session, or the record's own id, and $device_id for a session alone.
    # deviceidalways first, as its statement holds nodeviceid's.
    Mutant("deviceidalways", B,
           'if case .session = identity {\n            properties["$device_id"] = .string(distinctID)\n        }',
           'properties["$device_id"] = .string(distinctID)',
           mode="stmt"),
    Mutant("nodeviceid", B, 'properties["$device_id"] = .string(distinctID)', "", mode="stmt", nth=1),
    Mutant("nodistinctid", B, 'properties["distinct_id"] = .string(distinctID)', "", mode="stmt"),
    Mutant("distinctiduppercase", B, "identity.uuid.uuidString.lowercased()", "identity.uuid.uuidString"),
    Mutant("distinctidisrecord", B, "identity.uuid.uuidString.lowercased()", "record.deduplicationID"),
    Mutant("sensitivewritten", B, "properties = try reader.properties(of: record, includingSensitiveValues: false)", "properties = try reader.properties(of: record, includingSensitiveValues: true)", mode="stmt"),
    # The context.
    Mutant("nocontext", B, "record.mixpanelContext", "[String: JSON]()"),
    # Reserved event names. The catch's guard dropped, so a reserved name is reported before an
    # event the plan doesn't describe. First, as its statement holds the name check
    # reservedafterreaderror changes.
    Mutant("reservedbeforeunknown", B,
           'if case .unknownEvent = error {} else if record.name.hasPrefix("$") {\n                throw .reservedEventName(name: record.name)\n            }',
           'if record.name.hasPrefix("$") {\n                throw .reservedEventName(name: record.name)\n            }',
           mode="stmt"),
    Mutant("reservednameaccepted", B, '!record.name.hasPrefix("$")', "true"),
    # The second copy is the catch's, after reservedbeforeunknown's: a reserved event the reader
    # can't read.
    Mutant("reservedafterreaderror", B, 'record.name.hasPrefix("$")', "false", nth=1),
    # Reserved property names.
    Mutant("reservedpropertiesaccepted", B,
           "properties.keys.filter(\\.isReservedByMixpanel).min(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) })",
           "Optional<String>.none"),
    Mutant("reservedpropertylast", B,
           "properties.keys.filter(\\.isReservedByMixpanel).min(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) })",
           "properties.keys.filter(\\.isReservedByMixpanel).max(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) })"),
    Mutant("reservedpropertyunnamed", B, ".reservedPropertyName(event: record.name, property: reserved)", '.reservedPropertyName(event: record.name, property: "")'),
    # The two $ mutants hold `self == "token"`, so they come first, and tokenpropertyaccepted takes
    # the third copy, the original.
    Mutant("dollarpropertyaccepted", B, 'hasPrefix("$") || self == "token"', 'self == "token"'),
    Mutant("dollaranywhere", B, 'hasPrefix("$") || self == "token"', 'contains("$") || self == "token"'),
    Mutant("tokenpropertyaccepted", B, 'self == "token"', "false", nth=2),
    Mutant("timepropertyaccepted", B, 'self == "time"', "false"),
    Mutant("distinctidpropertyaccepted", B, 'self == "distinct_id"', "false"),
    Mutant("ippropertyaccepted", B, 'self == "ip"', "false"),
    Mutant("bucketpropertyaccepted", B, 'self == "bucket"', "false"),
    Mutant("propertynamecaseless", B, 'self == "time"', 'lowercased() == "time"'),
    # Skipped records' reasons.
    Mutant("propertyunnamed", B, ".unrepresentableValue(event: event, property: property)", '.unrepresentableValue(event: event, property: "")'),
    Mutant("notencodableasunknown", B, ".notEncodable(name: name)", "MixpanelEncodingError.unknownEvent(name: name, version: 1)"),
    Mutant("oversizedsizedropped", B, ".oversized(byteCount: byteCount)", ".oversized(byteCount: 0)"),
    # Mixpanel's limits on an event.
    Mutant("propertylimitinclusive", B, "properties.count < Self.propertyLimit", "properties.count <= Self.propertyLimit"),
    Mutant("propertylimitearly", B, "properties.count < Self.propertyLimit", "properties.count < 254"),
    Mutant("propertycountdropped", B, ".tooManyProperties(event: record.name, count: properties.count)", "MixpanelEncodingError.tooManyProperties(event: record.name, count: 0)"),
    Mutant("arraylimitexclusive", B, "count >= Self.arrayElementLimit", "count > Self.arrayElementLimit"),
    Mutant("arraylimitearly", B, "count >= Self.arrayElementLimit", "count >= 254"),
    Mutant("nestedarrayignored", B, "elements.compactMap(\\.longestArrayCount).reduce(elements.count, max)", "elements.count"),
    Mutant("arrayinobjectignored", B, "members.values.compactMap(\\.longestArrayCount).max()", "nil"),
    Mutant("arraypropertyunnamed", B, ".tooManyArrayElements(event: record.name, property: name, count: count)", 'MixpanelEncodingError.tooManyArrayElements(event: record.name, property: "", count: count)'),
    Mutant("lastpropertynamed", B, "properties.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) })", "properties.sorted(by: { $1.key.utf8.lexicographicallyPrecedes($0.key.utf8) })"),
    Mutant("depthlimitexclusive", B, "value.objectDepth <= Self.objectDepthLimit", "value.objectDepth < Self.objectDepthLimit"),
    Mutant("depthlimitlate", B, "value.objectDepth <= Self.objectDepthLimit", "value.objectDepth <= 4"),
    # Before arrayaddsdepth, whose new text holds the old.
    Mutant("depthinarrayignored", B, "elements.map(\\.objectDepth).max() ?? 0", "0"),
    Mutant("arrayaddsdepth", B, "elements.map(\\.objectDepth).max() ?? 0", "1 + (elements.map(\\.objectDepth).max() ?? 0)"),
    Mutant("shallowestmember", B, "members.values.map(\\.objectDepth).max()", "members.values.map(\\.objectDepth).min()"),
    Mutant("depthpropertyunnamed", B, ".nestedTooDeeply(event: record.name, property: name)", 'MixpanelEncodingError.nestedTooDeeply(event: record.name, property: "")'),
    Mutant("limitignored", B, "self.limit = limit", "self.limit = .unlimited", mode="stmt"),
    # The whole limit, as an expression mutant can't hold an argument label.
    Mutant("countlimitwrong", B, "(try? BatchLimit(maximumRecordCount: 2_000, maximumByteCount: 2_000_000, maximumRecordByteCount: 999_999)) ?? .unlimited", "(try? BatchLimit(maximumRecordCount: 50, maximumByteCount: 2_000_000, maximumRecordByteCount: 999_999)) ?? .unlimited"),
    Mutant("requestlimitwrong", B, "(try? BatchLimit(maximumRecordCount: 2_000, maximumByteCount: 2_000_000, maximumRecordByteCount: 999_999)) ?? .unlimited", "(try? BatchLimit(maximumRecordCount: 2_000, maximumByteCount: 10_000_000, maximumRecordByteCount: 999_999)) ?? .unlimited"),
    Mutant("recordlimitwrong", B, "(try? BatchLimit(maximumRecordCount: 2_000, maximumByteCount: 2_000_000, maximumRecordByteCount: 999_999)) ?? .unlimited", "(try? BatchLimit(maximumRecordCount: 2_000, maximumByteCount: 2_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited"),
    # The factory.
    Mutant("emptytokenaccepted", F, "!projectToken.isEmpty", "true"),
    Mutant("untrimmedtoken", F, "projectToken.trimmingCharacters(in: .whitespacesAndNewlines)", "projectToken"),
    Mutant("malformedaccepted", F, "projectToken.utf8.allSatisfy(\\.isASCIIAlphanumeric)", "true"),
    Mutant("nodigits", F, '(UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(self)', "false"),
    Mutant("nolowercase", F, '(UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(self)', "false"),
    Mutant("nouppercase", F, '(UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(self)', "false"),
    Mutant("slashaccepted", F, 'UInt8(ascii: "0")', 'UInt8(ascii: "/")'),
    Mutant("colonaccepted", F, 'UInt8(ascii: "9")', 'UInt8(ascii: ":")'),
    Mutant("backtickaccepted", F, 'UInt8(ascii: "a")', 'UInt8(ascii: "`")'),
    Mutant("braceaccepted", F, 'UInt8(ascii: "z")', 'UInt8(ascii: "{")'),
    Mutant("ataccepted", F, 'UInt8(ascii: "A")', 'UInt8(ascii: "@")'),
    Mutant("bracketaccepted", F, 'UInt8(ascii: "Z")', 'UInt8(ascii: "[")'),
    Mutant("bootstrappedinstrument", F, "NoOpInstrument()", "InstrumentationSystem.instrument"),
    # The endpoints. Before usaseu, which writes the EU endpoint again, these write the US one
    # again, so usaseu takes the first.
    Mutant("indianoipquery", F, '"https://api-in.mixpanel.com/track?ip=0&verbose=1"', '"https://api-in.mixpanel.com/track?verbose=1"'),
    Mutant("indiaasus", F, '"https://api-in.mixpanel.com/track?ip=0&verbose=1"', '"https://api.mixpanel.com/track?ip=0&verbose=1"'),
    Mutant("euasus", F, '"https://api-eu.mixpanel.com/track?ip=0&verbose=1"', '"https://api.mixpanel.com/track?ip=0&verbose=1"'),
    Mutant("usaseu", F, '"https://api.mixpanel.com/track?ip=0&verbose=1"', '"https://api-eu.mixpanel.com/track?ip=0&verbose=1"', nth=0),
    # Context.
    Mutant("noappversion", C, 'properties["$app_version_string"] = .string(version)', "", mode="stmt"),
    Mutant("noappbuild", C, 'properties["$app_build_number"] = .string(build)', "", mode="stmt"),
    Mutant("nomodel", C, 'properties["$model"] = .string(device.model)', "", mode="stmt"),
    Mutant("nowifi", C, 'properties["$wifi"] = .boolean(network == .wifi)', "", mode="stmt"),
    Mutant("wifialways", C, "network == .wifi", "true"),
    Mutant("wifiascellular", C, "network == .wifi", "network == .cellular"),
    Mutant("noos", C, 'properties["$os"] = .string(operatingSystem.name)', "", mode="stmt"),
    Mutant("osasversion", C, 'properties["$os"] = .string(operatingSystem.name)', 'properties["$os"] = .string(operatingSystem.version)', mode="stmt"),
    Mutant("noosversion", C, 'properties["$os_version"] = .string(operatingSystem.version)', "", mode="stmt"),
    # Mixpanel's backoff (TRAF-124). The factories' `backoff: ExponentialBackoff = .mixpanel`
    # default isn't planted: a public default argument can't call the internal mutant switch, and
    # with jitter drawn from the system generator no test could tell 1 s from 2 s for certain.
    Mutant("mixpanelbackoffinitial", F, "Duration.seconds(2)", "Duration.seconds(1)"),
    Mutant("mixpanelbackoffmaximum", F, "Duration.seconds(60)", "Duration.seconds(120)"),
    # The verbose answer (TRAF-123).
    # Quoted, as an expression can't sit inside a string literal. Applied after the endpoint
    # mutants, whose text holds the US literal on the EU and India lines and the EU literal on the
    # US line, so the US and EU ones pick their own line with nth.
    Mutant("usnotverbose", F, '"https://api.mixpanel.com/track?ip=0&verbose=1"', '"https://api.mixpanel.com/track?ip=0"', nth=0),
    Mutant("eunotverbose", F, '"https://api-eu.mixpanel.com/track?ip=0&verbose=1"', '"https://api-eu.mixpanel.com/track?ip=0"', nth=1),
    Mutant("innotverbose", F, '"https://api-in.mixpanel.com/track?ip=0&verbose=1"', '"https://api-in.mixpanel.com/track?ip=0"'),
    Mutant("statuszerodelivered", B, "return .rejected(reason: answer.error.flatMap { $0.isEmpty ? nil : $0 } ?? noValidEvent)", "return .delivered", mode="stmt"),
    # errorignored holds emptyerrorkept's text, so it comes first.
    Mutant("errorignored", B, "answer.error.flatMap { $0.isEmpty ? nil : $0 } ?? noValidEvent", "noValidEvent"),
    Mutant("emptyerrorkept", B, "$0.isEmpty ? nil : $0", "$0"),
    Mutant("verbosetwoaszero", B, "answer.status", "(answer.status == 2 ? 0 : answer.status)"),
    Mutant("verboseunknownrejected", B, "break", "return .rejected(reason: noValidEvent)", mode="stmt", nth=0),
    # verboseunknownrejected writes the same statement above it, so this picks the second.
    Mutant("barezerodelivered", B, "return .rejected(reason: noValidEvent)", "return .delivered", mode="stmt", nth=1),
    Mutant("bareunread", B, "try? decoder.decode(Int.self, from: response.body)", "Int?.none"),
    Mutant("bareunknownrejected", B, "break", "return .rejected(reason: noValidEvent)", mode="stmt", nth=1),
    Mutant("unreadablerejected", B, """logger.notice("Mixpanel answered \\(response.head.status) with a body its track API doesn't document; the request counts as delivered")
        return .delivered""", "return .rejected(reason: noValidEvent)", mode="stmt"),
    # The 5-day window and request deadlines (TRAF-135).
    Mutant("nowindow", B, "offset >= -Self.windowSeconds", "true", nth=1),
    Mutant("windowexclusive", B, "offset >= -Self.windowSeconds", "offset > -Self.windowSeconds", nth=1),
    Mutant("futureaccepted", B, "offset <= Self.latestOffset", "true", nth=1),
    Mutant("futureexclusive", B, "offset <= Self.latestOffset", "offset < Self.latestOffset", nth=1),
    Mutant("windowfivedays", B, "(5 * 24 - 1) * 60 * 60", "5 * 24 * 60 * 60"),
    Mutant("clockperrecord", B, "json(of: record, encodedAt: encodedAt)", "json(of: record, encodedAt: now())"),
    Mutant("nodeadline", B, "return try limit.requests(for: batch, in: .array, maximumAge: Self.window, encoding: encoding, oversized: oversized)", "return limit.requests(for: batch, in: .array, encoding: encoding, oversized: oversized)", mode="stmt"),
    Mutant("factorynowignored", F, "MixpanelBatchEncoder(projectToken: projectToken, plan: plan, now: now)", "MixpanelBatchEncoder(projectToken: projectToken, plan: plan)"),
    Mutant("destinationnowignored", F, """return HTTPDestination(
            endpoint: region.endpoint,
            instrument: instrument,
            transport: transport,
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            // One clock for both, so the 119 hours a record is checked against when its batch is
            // encoded are the ones its request's deadline ends.
            now: now)""", """return HTTPDestination(
            endpoint: region.endpoint,
            instrument: instrument,
            transport: transport,
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            now: { Date.now })""", mode="stmt"),
]
