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
    Mutant("defaultnamelowercased", E, "String(describing: Self.self)", "String(describing: Self.self).lowercased()"),
]
