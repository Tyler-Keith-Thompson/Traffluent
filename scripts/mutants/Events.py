# Planted bugs for Events; run with `just mutate Events`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Events/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (they survive by design):
# - Dropping `hasher.combine(keyword)` from Constraint's hash: equal constraints still hash
#   alike, which is all Hashable asks; only a hash-quality measurement could tell.
# - Event's default `constraintViolation()` returning a violation: its text, `{ nil }`, isn't
#   unique in the file to plant; EventConstraintTests pins the default.
# - A pattern check's fallback when the pattern doesn't compile: the factory compiled it already,
#   so the fallback can't run.

TESTS = ["EventsTests"]

L = "SourceLocation.swift"
R = "EventRecord.swift"
E = "Event.swift"
K = "ConsentCategory.swift"
V = "Sensitive.swift"
S = "EventSchema.swift"

C = "Constraint.swift"
RF = "Refined.swift"
VK = "ValidationKeyword.swift"
CV = "ConstraintViolation.swift"

MUTANTS = [
    Mutant("modulewholefileid", L, 'String(fileID.prefix { $0 != "/" })', "fileID"),
    Mutant("modulestopsatdot", L, '$0 != "/"', '$0 != "."'),
    Mutant("filefromfileid", L, "self.file = file", "self.file = fileID", mode="stmt"),
    Mutant("fileidfromfile", L, "self.fileID = fileID", "self.fileID = file", mode="stmt"),
    Mutant("functionempty", L, "self.function = function", 'self.function = ""', mode="stmt"),
    Mutant("linefromcolumn", L, "self.line = line", "self.line = column", mode="stmt"),
    Mutant("columnfromline", L, "self.column = column", "self.column = line", mode="stmt"),
    Mutant("recordnamefixed", R, "type(of: event).name", '"Event"'),
    Mutant("recordtimestampfixed", R, "self.timestamp = timestamp", "self.timestamp = Date(timeIntervalSince1970: 0)", mode="stmt"),
    Mutant("recordcontextdropped", R, "self.context = context", "self.context = .topLevel", mode="stmt"),
    Mutant("redeliveredforced", R, "self.isRedelivered = isRedelivered", "self.isRedelivered = true", mode="stmt"),
    Mutant("redeliveredignored", R, "self.isRedelivered = isRedelivered", "self.isRedelivered = false", mode="stmt"),
    Mutant("tagdropped", R, "self.deliveryTag = deliveryTag", "self.deliveryTag = nil", mode="stmt"),
    # The default, after the `false`s of the doc comments before it.
    Mutant("defaultredelivered", R, "false", "true", nth=2),
    Mutant("tagpositionzero", "DeliveryTag.swift", "self.position = position", "self.position = 0", mode="stmt"),
    Mutant("defaultnamelowercased", E, "String(describing: Self.self)", "String(describing: Self.self).lowercased()"),
    Mutant("defaultcategory", E, ".analytics", ".advertising"),
    Mutant("recordcategoryfixed", R, "type(of: event).consentCategory", ".analytics"),
    Mutant("revealsredacted", R, "revealsSensitiveValues ? sensitive.value : nil", "sensitive.value"),
    Mutant("recordreveals", R, "revealsSensitiveValues = false", "revealsSensitiveValues = true", mode="stmt"),
    Mutant("categoryunnamed", K, "self.name = name", 'self.name = ""', mode="stmt"),
    Mutant("advertisingnamed", K, 'ConsentCategory("advertising")', 'ConsentCategory("analytics")'),
    Mutant("descriptionreveals", V, '"<redacted>"', '"\\(value)"', nth=0),
    Mutant("debugdescriptionreveals", V, '"Sensitive(<redacted>)"', '"Sensitive(\\(value))"'),
    Mutant("mirrorreveals", V, "Mirror(self, children: [], displayStyle: .struct)", 'Mirror(self, children: ["value": value], displayStyle: .struct)'),
    Mutant("propertyunnamed", S, "            self.name = name", '            self.name = ""', mode="stmt"),
    Mutant("propertytypeunnamed", S, "            self.typeName = typeName", '            self.typeName = ""', mode="stmt"),
    Mutant("propertyneveroptional", S, "            self.isOptional = isOptional", "            self.isOptional = false", mode="stmt"),
    # The schema's own `self.name = name`, after the property's, which holds the text too.
    Mutant("schemaunnamed", S, "        self.name = name", '        self.name = ""', mode="stmt", nth=1),
    Mutant("schemaversionzero", S, "        self.version = version", "        self.version = 0", mode="stmt"),
    Mutant("schemaconsentfixed", S, "        self.consentCategory = consentCategory", "        self.consentCategory = .analytics", mode="stmt"),
    Mutant("schemanoproperties", S, "        self.properties = properties", "        self.properties = []", mode="stmt"),
    # Constraint: each keyword's check, its bound included, and its traps.
    Mutant("minlengthexclusive", C, "$0.unicodeScalars.count >= length", "$0.unicodeScalars.count > length"),
    Mutant("minlengthcharacters", C, "$0.unicodeScalars.count >= length", "$0.count >= length"),
    Mutant("maxlengthexclusive", C, "$0.unicodeScalars.count <= length", "$0.unicodeScalars.count < length"),
    Mutant("maxlengthcharacters", C, "$0.unicodeScalars.count <= length", "$0.count <= length"),
    Mutant("negativeminlength", C, "length >= 0", "length >= -1", nth=0),
    Mutant("negativemaxlength", C, "length >= 0", "length >= -1", nth=1),
    Mutant("patternalwaysmatches", C, "return value.contains(regex)", "return true", mode="stmt"),
    Mutant("exampleunchecked", C, 'precondition(example.contains(regex), "The pattern \\(pattern) doesn\'t match its example \\(example)")', "", mode="stmt"),
    Mutant("invalidpatternaccepted", C, 'preconditionFailure("The pattern \\(pattern) isn\'t a valid regular expression")', "return Constraint(.pattern(pattern, example: example)) { _ in true }", mode="stmt"),
    # The integer bounds come first in the file, then the floating-point ones.
    Mutant("integerminimumexclusive", C, "$0 >= bound", "$0 > bound", nth=0),
    Mutant("floatminimumexclusive", C, "$0 >= bound", "$0 > bound", nth=1),
    Mutant("integermaximumexclusive", C, "$0 <= bound", "$0 < bound", nth=0),
    Mutant("floatmaximumexclusive", C, "$0 <= bound", "$0 < bound", nth=1),
    Mutant("integerminimumkeyword", C, ".minimum(Double(bound))", ".maximum(Double(bound))", nth=0),
    Mutant("infiniteminimum", C, "bound.isFinite", "true", nth=0),
    Mutant("infinitemaximum", C, "bound.isFinite", "true", nth=1),
    Mutant("minitemsexclusive", C, "$0.count >= count", "$0.count > count"),
    Mutant("maxitemsexclusive", C, "$0.count <= count", "$0.count < count"),
    Mutant("negativeminitems", C, "count >= 0", "count >= -1", nth=0),
    Mutant("negativemaxitems", C, "count >= 0", "count >= -1", nth=1),
    Mutant("constraintsallequal", C, "lhs.keyword == rhs.keyword", "true"),
    # Refined: the plain spelling's trap, the checked spelling's error, and the conformances.
    Mutant("plainnottrapped", RF, 'preconditionFailure("Refined<\\(Value.self), \\(Rule.self)>: the value breaks \\(broken.keyword)")', "", mode="stmt"),
    Mutant("checkednotthrown", RF, "throw broken.keyword.unsatisfied", "", mode="stmt"),
    Mutant("lastbroken", RF, "Rule.constraints.first(where: { !$0.isSatisfied(by: value) })", "Rule.constraints.last(where: { !$0.isSatisfied(by: value) })", nth=1),
    Mutant("comparereversed", RF, "lhs.value < rhs.value", "lhs.value > rhs.value"),
    Mutant("refineddescriptionempty", RF, "String(describing: value)", '""'),
    Mutant("refinedkeywordsnone", RF, "Rule.constraints.map(\\.keyword)", "[]"),
    # ValidationKeyword: the keywords of a type, forwarded through Optional and Sensitive.
    Mutant("keywordsofnone", VK, "(type as? any RefinedKeywords.Type)?.keywords ?? []", "[]"),
    Mutant("keypathkeywordsnone", VK, "keywords(of: Value.self)", "[]"),
    Mutant("optionalnotforwarded", VK, "Wrapped.keywords", "[]"),
    Mutant("sensitivenotforwarded", VK, "Value.keywords", "[]"),
    Mutant("minlengthdescribed", VK, '"minLength \\(length)"', '"maxLength \\(length)"'),
    Mutant("patterndescribed", VK, '"pattern \\(pattern)"', '"pattern \\(pattern)$"'),
    Mutant("wholeboundfraction", VK, "return String(Int64(self))", "return description", mode="stmt"),
    Mutant("hugeboundinteger", VK, "abs(self) <= 9_007_199_254_740_992", "true"),
    Mutant("violationunnamed", CV, "self.property = property", 'self.property = ""', mode="stmt"),
    Mutant("violationkeywordfixed", CV, "self.keyword = keyword", "self.keyword = .minLength(0)", mode="stmt"),
    Mutant("violationdescribed", CV, '"\\"\\(property)\\" breaks \\(keyword)"', '"\\(property) breaks \\(keyword)"'),
    Mutant("schemakeywordsdropped", S, "            self.keywords = keywords", "            self.keywords = []", mode="stmt"),
]
