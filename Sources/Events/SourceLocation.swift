/// Where in source code an event was tracked.
///
/// A pipeline captures each field from its caller's default arguments, so the location is the
/// line that called `track`, not a line inside the library.
public struct SourceLocation: Sendable, Hashable {
    /// The file, as `#file` gives it. In the Swift 6 language mode this is the same as ``fileID``.
    public var file: String
    /// The module and file name, as `#fileID` gives it: `"MyApp/Checkout.swift"`.
    public var fileID: String
    /// The enclosing declaration, as `#function` gives it: `"checkout(cart:)"`.
    public var function: String
    /// The line number, counting from 1.
    public var line: Int
    /// The column number, counting from 1.
    public var column: Int

    /// A location from its parts.
    ///
    /// - Parameters:
    ///   - file: The file, as `#file` gives it.
    ///   - fileID: The module and file name, as `#fileID` gives it.
    ///   - function: The enclosing declaration, as `#function` gives it.
    ///   - line: The line number.
    ///   - column: The column number.
    public init(file: String, fileID: String, function: String, line: Int, column: Int) {
        self.file = file
        self.fileID = fileID
        self.function = function
        self.line = line
        self.column = column
    }

    /// The module the event was tracked in: ``fileID`` up to its first `/`, or all of it when it
    /// has none.
    ///
    /// - Complexity: O(*n*), where *n* is the length of the module's name.
    public var moduleName: String {
        String(fileID.prefix { $0 != "/" })
    }
}
