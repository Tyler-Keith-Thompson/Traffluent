# Planted bugs for MatomoEncoding; run with `just mutate MatomoEncoding`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/MatomoEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Mutants are applied in this order, so one whose `old` holds another's
# comes first. Every mutant must be caught; one that survives needs a test, or a note here saying
# why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The properties PropertyJSON reads (its PropertyReader), identity and batch splitting:
#   PropertyJSON's spec plants those.
# - The unknownEvent arm of `MatomoEncodingError.init(_ error: PropertyReadingError)` mapped to
#   another case: the catch in json(of:) only reaches it for an event the plan doesn't describe,
#   and the unknownEvent tests pin the case it maps to.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
# - `text.reserveCapacity(16)` in matomoVisitorID: capacity alone changes no result.
# - `guard let endpoint = components.url`: URLComponents that came from a URL, given a path that
#   was its own percent-encoded path, always make a URL.
# - The `?? self` of percentEncodedForQuery and the `?? .unlimited` of batchLimit: a Swift String
#   is always valid Unicode, and the limit's arguments are valid.
# - maximumRecordByteCount anywhere from 999,985 up: a body holds a record inside the 15 bytes of
#   `{"requests":[` and `]}`, so its 1,000,000 bytes bind first. The oversized test sends a record
#   of 999,985 bytes and skips one of 999,986, and recordbytes999984 below pins the record limit.
# - holdsSensitive's `?.count == 1` for a bare `Sensitive`: the only expression holding it also
#   holds sensitiveeventsonly's and sensitiveanymodule's, which mutate.py can't nest, and a bare
#   `Sensitive` doesn't compile in an event; the sensitive-type tests list it.
# - Either bound of the window written so that a NaN offset passes it (`!(offset < -window)`):
#   the other bound still refuses NaN, so the record is still skipped. Only both together let a
#   clock that isn't finite through, which mutate.py can't plant as one mutant; the non-finite
#   clock tests pin the outcome.
# - The notices the encoder's initializer logs for unmapped properties and refused names: logs
#   are for developers, and tests don't pin them (AGENTS.md, Logging).
# - The notice's logger.notice line removed on its own, leaving `count += 1`: the count is what
#   tests read, as tests don't pin logs (AGENTS.md). noticenotlogged removes the log and its
#   count together.
# - A process-wide notice in place of the encoder's: mutate.py's schemata can't declare the
#   global it would need. factoryDestinationsLogTheirOwn and encodersLogTheirOwn pin that each
#   destination's encoder has its own.
# - Mutants only a case pattern could hold, which mutate.py's switches can't: one scalar dropped
#   from isTrimmedByPHP or from matomoStoredValue's removed or escaped ones, and a string
#   dimension value written as JSON (the dimensions tests send strings unquoted). The category and
#   event-name tests and the property test against a naive reference cover each scalar.

TESTS = ["MatomoEncodingTests"]

B = "MatomoBatchEncoder.swift"
D = "MatomoDimensions.swift"
F = "HTTPDestination+Matomo.swift"
S = "String+MatomoValues.swift"
U = "UUID+MatomoVisitorID.swift"

LIMIT = "BatchLimit(maximumRecordCount: 20, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"
NAME_CHECK_ON_FAILURE = "if case .unknownEvent = error {} else {\n                try record.checkMatomoName()\n            }"
LOCALE = 'if let locale = record.context[LocaleKey.self] {\n            parameters.append(("lang", locale.identifier(.bcp47)))\n        }'

MUTANTS = [
    # The limits.
    Mutant("batchcount21", B, LIMIT, "BatchLimit(maximumRecordCount: 21, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchcount19", B, LIMIT, "BatchLimit(maximumRecordCount: 19, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchbytes1000001", B, LIMIT, "BatchLimit(maximumRecordCount: 20, maximumByteCount: 1_000_001, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchbytes999999", B, LIMIT, "BatchLimit(maximumRecordCount: 20, maximumByteCount: 999_999, maximumRecordByteCount: 1_000_000)"),
    Mutant("recordbytes999984", B, LIMIT, "BatchLimit(maximumRecordCount: 20, maximumByteCount: 1_000_000, maximumRecordByteCount: 999_984)"),
    Mutant("oversizedbytecount", B, ".oversized(byteCount: byteCount)", "MatomoEncodingError.oversized(byteCount: 0)"),
    Mutant("limitignored", B, "self.limit = limit", "self.limit = MatomoBatchEncoder.batchLimit", mode="stmt"),
    Mutant("window24h", B, "23 * 60 * 60", "24 * 60 * 60"),
    Mutant("window22h", B, "23 * 60 * 60", "22 * 60 * 60"),
    Mutant("actionlength4097", B, "4096", "4097"),
    Mutant("actionlength4095", B, "4096", "4095"),
    Mutant("dimensionlength251", B, "250", "251"),
    Mutant("dimensionlength249", B, "250", "249"),

    # The setup checks.
    Mutant("siteidzero", B, "siteID >= 1", "siteID >= 0"),
    Mutant("anysiteid", B, "siteID >= 1", "true"),
    Mutant("anycategory", B, "category.isMatomoAction", "true"),
    Mutant("emptyaction", B, "length >= 1 && length <= MatomoBatchEncoder.actionLength", "length <= MatomoBatchEncoder.actionLength"),
    Mutant("longaction", B, "length >= 1 && length <= MatomoBatchEncoder.actionLength", "length >= 1"),
    Mutant("dimensionzero", D, "$0.dimension < 1", "$0.dimension < 0"),
    Mutant("anydimension", D, "$0.dimension < 1", "false"),
    Mutant("duplicatesallowed", D, "dimensions.updateValue(mapping.dimension, forKey: mapping.property) == nil", "{ dimensions[mapping.property] = mapping.dimension; return true }()"),
    Mutant("unknownallowed", D, "mappings.first(where: { !properties.contains($0.property) })", "nil"),
    Mutant("sharedallowed", D, "used.insert(dimension).inserted", "true"),
    Mutant("sensitiveallowed", D, "dimensions[$0.name] != nil && $0.isSensitive", "false"),
    Mutant("sensitiveunmappedrefused", D, "dimensions[$0.name] != nil && $0.isSensitive", "$0.isSensitive"),
    Mutant("sensitiveunparsed", D, "WrittenType(parsing: typeName)?.holdsSensitive ?? false", "WrittenType(parsing: typeName)?.holdsSensitive ?? true"),
    Mutant("sensitivewrappednot", D, "wrapped.holdsSensitive", "false"),
    Mutant("sensitivegenericnot", D, "arguments[0].holdsSensitive", "false"),
    Mutant("sensitiveeventsonly", D, 'names("Sensitive", in: ["Events", "Traffluent"])', 'names("Sensitive", in: ["Events"])'),
    Mutant("sensitiveanymodule", D, 'names("Sensitive", in: ["Events", "Traffluent"])', 'names("Sensitive", in: ["Events", "Traffluent", "Other"])'),
    Mutant("sensitivenoarray", D, 'names("Optional", in: ["Swift"]) ?? names("Array", in: ["Swift"])', 'names("Optional", in: ["Swift"])'),
    Mutant("dictionarydescending", D, "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)"),
    Mutant("unmappedallmapped", D, "!mapped.contains($0.name)", "false"),
    Mutant("unmappedinverted", D, "!mapped.contains($0.name)", "mapped.contains($0.name)"),

    # The URL.
    Mutant("httpallowed", F, 'components.scheme?.lowercased() == "https"', 'components.scheme?.lowercased().hasPrefix("http") == true'),
    Mutant("schemecase", F, 'components.scheme?.lowercased() == "https"', 'components.scheme == "https"'),
    Mutant("nohost", F, "components.percentEncodedHost?.isEmpty == false", "true"),
    Mutant("userallowed", F, "components.percentEncodedUser == nil", "true"),
    Mutant("queryallowed", F, "components.percentEncodedQuery == nil", "true"),
    Mutant("fragmentallowed", F, "components.percentEncodedFragment == nil", "true"),
    Mutant("phpallowed", F, 'path.split(separator: "/").last?.lowercased().hasSuffix(".php") != true', "true"),
    Mutant("phpcase", F, 'path.split(separator: "/").last?.lowercased().hasSuffix(".php")', 'path.split(separator: "/").last?.hasSuffix(".php")'),
    Mutant("phpanywhere", F, 'path.split(separator: "/").last?.lowercased().hasSuffix(".php")', 'path.lowercased().contains(".php")'),
    Mutant("slasheskept", F, "path.removeLast()", "break", mode="stmt"),
    # The first occurrence, read; the second is the path written back.
    Mutant("decodedpath", F, "components.percentEncodedPath", "components.path", nth=0),
    Mutant("piwikendpoint", F, '"/matomo.php"', '"/piwik.php"'),
    Mutant("nowignored", F, "MatomoBatchEncoder(siteID: siteID, dimensions: dimensions, category: category, plan: plan, now: now)", "MatomoBatchEncoder(siteID: siteID, dimensions: dimensions, category: category, plan: plan)"),
    # Deadlines (TRAF-134). The first `Self.window` is the request's deadline. The catch that sends
    # requests without a deadline is reached only through a negative age, which deadlinenegative
    # plants; a mutant inside it would be the same as that one. deadlinenegative comes first, as the
    # first `Self.window` after deadline24h's is the one inside its mutated branch.
    Mutant("deadlinenegative", B, "Self.window", "Duration.seconds(-1)", nth=0),
    Mutant("deadline24h", B, "Self.window", "Self.window + .seconds(60 * 60)", nth=0),
    Mutant("destinationnowignored", F, """return HTTPDestination(
            endpoint: endpoint,
            instrument: instrument,
            transport: transport,
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            // One clock for both, so the 23 hours a record is checked against when its batch is
            // encoded are the ones its request's deadline ends.
            now: now)""", """return HTTPDestination(
            endpoint: endpoint,
            instrument: instrument,
            transport: transport,
            encoder: encoder,
            backoff: backoff,
            clock: clock,
            now: { Date.now })""", mode="stmt"),

    # The skipped records and their order.
    # The second occurrence, after a record is read; the first is in the reader's catch.
    Mutant("namenotchecked", B, "try record.checkMatomoName()", "", mode="stmt", nth=1),
    Mutant("namecheckedwhenunknown", B, NAME_CHECK_ON_FAILURE, "try record.checkMatomoName()", mode="stmt"),
    Mutant("namenotcheckedonfailure", B, NAME_CHECK_ON_FAILURE, "", mode="stmt"),
    # The second occurrence, in checkMatomoName: the first is the notice's `schema.name`.
    Mutant("anyeventname", B, "name.isMatomoAction", "true", nth=1),
    Mutant("timestamprounded", B, "record.timestamp.timeIntervalSince1970.rounded(.down)", "record.timestamp.timeIntervalSince1970.rounded()"),
    Mutant("timestamptruncated", B, "record.timestamp.timeIntervalSince1970.rounded(.down)", "record.timestamp.timeIntervalSince1970.rounded(.towardZero)"),
    Mutant("nopast", B, "offset >= -Self.windowSeconds", "true"),
    Mutant("nofuture", B, "offset <= Self.windowSeconds", "true"),
    Mutant("pastexclusive", B, "offset >= -Self.windowSeconds", "offset > -Self.windowSeconds"),
    Mutant("futureexclusive", B, "offset <= Self.windowSeconds", "offset < Self.windowSeconds"),
    Mutant("clockperrecord", B, "json(of: record, encodedAt: encodedAt)", "json(of: record, encodedAt: now())"),
    Mutant("sensitivesent", B, "properties = try reader.properties(of: record, includingSensitiveValues: false)", "properties = try reader.properties(of: record, includingSensitiveValues: record.revealsSensitiveValues)", mode="stmt"),
    Mutant("dimensionlengthunchecked", B, "length <= Self.dimensionValueLength", "true"),
    Mutant("dimensionrawlength", B, "value.value.matomoStoredLength", "value.value.count"),
    Mutant("dimensionlengthreported", B, ".dimensionValueTooLong(event: record.name, property: value.property, dimension: value.dimension, length: length)", "MatomoEncodingError.dimensionValueTooLong(event: record.name, property: value.property, dimension: value.dimension, length: 0)"),

    # The request.
    Mutant("sitename", B, '"idsite"', '"siteid"'),
    Mutant("recname", B, '"rec"', '"record"'),
    Mutant("apivname", B, '"apiv"', '"api"'),
    Mutant("caname", B, '"ca"', '"c"'),
    Mutant("visitorfromrecord", B, "record.pseudonymousIdentity.uuid.matomoVisitorID", "record.id.matomoVisitorID"),
    Mutant("cdtmilliseconds", B, "String(seconds)", "String(seconds * 1000)"),
    Mutant("categoryname", B, '"e_c"', '"e_n"'),
    Mutant("actionname", B, '"e_a"', '"e_n"'),
    Mutant("nolang", B, LOCALE, "", mode="stmt"),
    Mutant("langidentifier", B, "locale.identifier(.bcp47)", "locale.identifier"),
    Mutant("dimensionsunsorted", B, "values.sorted(by: { $0.dimension < $1.dimension })", "values"),
    Mutant("dimensionsdescending", B, "$0.dimension < $1.dimension", "$0.dimension > $1.dimension"),
    Mutant("nodimensions", B, 'parameters.append(("dimension\\(value.dimension)", value.value))', "", mode="stmt"),
    Mutant("noquestionmark", B, '"?"', '""'),
    Mutant("unescaped", B, "$0.value.percentEncodedForQuery", "$0.value"),
    # The fourth occurrence, the code's; the first three are in comments.
    Mutant("nullsent", B, "nil", '"null"', nth=3),

    # The stored length.
    Mutant("linebreakskept", S, "continue", "escaped.append(scalar)", mode="stmt"),
    Mutant("noescapes", S, 'escaped.append(contentsOf: "&amp;".unicodeScalars)', "escaped.append(scalar)", mode="stmt"),
    Mutant("quoteshort", S, '"&#039;"', '"&#39;"'),
    Mutant("notrimstart", S, "start = escaped.index(after: start)", "break", mode="stmt"),
    Mutant("notrimend", S, "end = escaped.index(before: end)", "break", mode="stmt"),
    Mutant("lengthinbytes", S, "matomoStoredValue.unicodeScalars.count", "matomoStoredValue.utf8.count"),
    Mutant("lengthincharacters", S, "matomoStoredValue.unicodeScalars.count", "matomoStoredValue.count"),
    Mutant("plusunescaped", S, '"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"', '"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+"'),
    Mutant("queryallowedset", S, ".urlUnreserved", "CharacterSet.urlQueryAllowed"),

    # The visitor.
    Mutant("hexupper", U, '"0123456789abcdef"', '"0123456789ABCDEF"'),
    Mutant("hexnibbles", U, "text.append(digits[Int(byte >> 4)])\n            text.append(digits[Int(byte & 0x0F)])", "text.append(digits[Int(byte & 0x0F)])\n            text.append(digits[Int(byte >> 4)])", mode="stmt"),
    Mutant("firstbytes", U, "[bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]", "[bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]"),
    Mutant("bytesreversed", U, "[bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15]", "[bytes.15, bytes.14, bytes.13, bytes.12, bytes.11, bytes.10, bytes.9, bytes.8]"),
    # The bulk answer's counts (TRAF-123).
    Mutant("negativetrackedread", B, "answer.tracked >= 0", "true"),
    Mutant("negativeinvalidread", B, "answer.invalid >= 0", "true"),
    Mutant("sentcountshort", B, "request.recordIDs.count", "(request.recordIDs.count - 1)"),
    # shortfallignored holds shortfallinclusive's text, so it comes first.
    Mutant("shortfallignored", B, "answer.tracked < sent && answer.invalid < sent - answer.tracked", "false"),
    Mutant("shortfallinclusive", B, "answer.invalid < sent - answer.tracked", "answer.invalid <= sent - answer.tracked"),
    Mutant("bothzeroignored", B, "(answer.tracked == 0 && answer.invalid == 0)", "false"),
    Mutant("transientrejected", B, """return .transient(reason: "Matomo counted \\(answer.tracked) tracked and \\(answer.invalid) invalid of the request's \\(sent) tracking requests, and skipped the rest")""", 'return .rejected(reason: "")', mode="stmt"),
    Mutant("nonetrackeddelivered", B, "answer.tracked > 0", "answer.tracked >= 0"),
    Mutant("allinvaliddelivered", B, """return .rejected(reason: "Matomo refused all \\(answer.invalid) of the request's tracking requests as invalid, as it does for a site ID of no site")""", "return .delivered", mode="stmt"),
    Mutant("unreadablerejected", B, "return .delivered", 'return .rejected(reason: "")', mode="stmt", nth=0),
    # The rejection's count of invalid requests. Last of the counts, as allinvaliddelivered's text
    # holds it, and after shortfallinclusive's text adds one: the shortfall's two, the both-0
    # check's and the transient reason's come before it (the negative-count guard is in
    # BulkAnswer, after outcome).
    Mutant("invalidcountlost", B, "answer.invalid", "0", nth=4),

    # The notice of a 2xx answer without tracking counts (TRAF-155).
    Mutant("noticeforbulkanswer", B, "guard BulkAnswer(reading: response.body) == nil else { return }", "", mode="stmt"),
    Mutant("noticenevercalled", B, "answerWithoutCountsNotice.logIfFirst(to: Self.logger)", "", mode="stmt"),
    # The logging path: logged for every such answer, never, or uncounted.
    Mutant("noticeeverytime", B, "guard count == 0 else { return }", "", mode="stmt"),
    Mutant("noticeafterfirst", B, "count == 0", "count == 1"),
    Mutant("noticenotlogged", B, """logger.notice("Matomo's answer holds no tracking counts, as with QueuedTracking's queue on: tracking requests the server refuses won't be reported")
            count += 1""", "", mode="stmt"),
    Mutant("noticeuncounted", B, "count += 1", "", mode="stmt"),
]
