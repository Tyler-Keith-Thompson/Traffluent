import Foundation
public import HTTPDestinations
public import JSONValues

/// The JSON a request body wraps a batch's records in: a bare array, or an object holding the
/// array under one member, beside members every request repeats (a key, a schema).
///
/// ```swift
/// // {"api_key":"phc_…","batch":[…]}
/// let envelope = JSONEnvelope(["api_key": .string(projectToken)], arrayMember: "batch")
/// ```
///
/// A body is what `JSON.minified` writes for the envelope with the records' JSON as the array:
/// no whitespace, and object members in the order of their names' UTF-8 bytes.
public struct JSONEnvelope: Sendable, Hashable {
    /// The body's text before the array's first element, its opening bracket included.
    private let prefix: String
    /// The body's text after the array's last element, its closing bracket included.
    private let suffix: String

    /// A bare JSON array of the records: `[…]`.
    public static let array = JSONEnvelope(prefix: "[", suffix: "]")

    /// An object of `members`, with the records as an array under `arrayMember`.
    ///
    /// - Parameters:
    ///   - members: The members every request repeats. A member named `arrayMember` is replaced
    ///     by the array.
    ///   - arrayMember: The name of the member that holds the records.
    public init(_ members: [String: JSON], arrayMember: String) {
        // A member named arrayMember precedes it and follows it in neither filter below, so the
        // array replaces it.
        let sorted = members
            .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            .map { (key: $0.key, text: JSON.string($0.key).minified + ":" + $0.value.minified) }
        let before = sorted.filter { $0.key.utf8.lexicographicallyPrecedes(arrayMember.utf8) }.map(\.text)
        let after = sorted.filter { arrayMember.utf8.lexicographicallyPrecedes($0.key.utf8) }.map(\.text)
        let array = JSON.string(arrayMember).minified + ":["
        prefix = "{" + (before + [array]).joined(separator: ",")
        suffix = "]" + after.map { "," + $0 }.joined() + "}"
    }

    private init(prefix: String, suffix: String) {
        self.prefix = prefix
        self.suffix = suffix
    }

    /// The UTF-8 bytes the envelope adds to its elements: everything in a body but them and the
    /// commas between them.
    public var byteCount: Int {
        prefix.utf8.count + suffix.utf8.count
    }

    /// The body of `elements` in the envelope, of content type `application/json`.
    ///
    /// - Parameter elements: Each record's JSON, minified (`JSON.minified`), in order.
    /// - Returns: The body.
    /// - Complexity: O(*n*) in the elements' length.
    public func body(of elements: [String]) -> EncodedBatch {
        EncodedBatch(body: Data((prefix + elements.joined(separator: ",") + suffix).utf8), contentType: "application/json")
    }
}
