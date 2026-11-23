# Planted bugs for Events; run with `just mutate Events`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Events/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (they survive by design): none.

TESTS = ["EventsTests"]

L = "SourceLocation.swift"
R = "EventRecord.swift"
E = "Event.swift"
K = "ConsentCategory.swift"
V = "Sensitive.swift"
S = "EventSchema.swift"

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
    Mutant("schemanoproperties", S, "        self.properties = properties", "        self.properties = []", mode="stmt"),
]
