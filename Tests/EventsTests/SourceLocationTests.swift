import Events
import Testing

@Suite("SourceLocation")
struct SourceLocationTests {
    @Test("The module name is the file ID up to its first slash")
    func moduleName() {
        let sut = Events.SourceLocation(file: "MyApp/Checkout.swift", fileID: "MyApp/Checkout.swift", function: "pay()", line: 3, column: 9)
        let expected = "MyApp"

        let actual = sut.moduleName

        #expect(actual == expected)
    }

    @Test("A file ID with no slash is all module name")
    func moduleNameWithoutSlash() {
        let sut = Events.SourceLocation(file: "Checkout.swift", fileID: "Checkout.swift", function: "pay()", line: 1, column: 1)
        let expected = "Checkout.swift"

        let actual = sut.moduleName

        #expect(actual == expected)
    }

    @Test("An empty file ID has an empty module name")
    func moduleNameOfEmptyFileID() {
        let sut = Events.SourceLocation(file: "", fileID: "", function: "", line: 1, column: 1)
        let expected = ""

        let actual = sut.moduleName

        #expect(actual == expected)
    }

    @Test("Only the first slash ends the module name")
    func moduleNameStopsAtFirstSlash() {
        let sut = Events.SourceLocation(file: "A/B/C.swift", fileID: "A/B/C.swift", function: "f()", line: 1, column: 1)
        let expected = "A"

        let actual = sut.moduleName

        #expect(actual == expected)
    }

    @Test("The initializer keeps every part as given")
    func initializer() {
        let expectedFile = "/src/MyApp/Checkout.swift"
        let expectedFileID = "MyApp/Checkout.swift"
        let expectedFunction = "pay(amount:)"
        let expectedLine = 12
        let expectedColumn = 5

        let actual = Events.SourceLocation(file: expectedFile, fileID: expectedFileID, function: expectedFunction, line: expectedLine, column: expectedColumn)

        #expect(actual.file == expectedFile)
        #expect(actual.fileID == expectedFileID)
        #expect(actual.function == expectedFunction)
        #expect(actual.line == expectedLine)
        #expect(actual.column == expectedColumn)
    }
}
