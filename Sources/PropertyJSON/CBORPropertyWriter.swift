internal import CBOR
import Foundation
internal import JSONValues
internal import TrackingPlans

/// Writes an event's properties as JSON holds them back to the CBOR map its `Decodable`
/// conformance reads, guided by each property's type as its schema writes it: the inverse of
/// `CBORPropertyReader`.
///
/// The JSON alone doesn't say what the event's conformance reads: a `Date` is an ISO 8601 string
/// that `@Event` reads as a double of its seconds since 2001, and a whole `Double` is written
/// without a fraction, which would read as an integer. The written type says which.
struct CBORPropertyWriter {
    /// The map of `properties`, each written through its type in `types`.
    ///
    /// - Parameters:
    ///   - properties: The event's properties, by name, as JSON holds them.
    ///   - types: Each property's type as written; a missing or `nil` one is written for what the
    ///     JSON holds.
    /// - Throws: ``UndecodableProperty`` naming the property whose value isn't one its type is
    ///   written as.
    func map(of properties: [String: JSON], types: [String: WrittenType?]) throws(UndecodableProperty) -> CBOR {
        var entries: [CBOR: CBOR] = [:]
        // By name, so of two values that don't match their types, the error always names the same one.
        for (name, value) in properties.sorted(by: { $0.key < $1.key }) {
            do {
                entries[.textString(name)] = try cbor(value, as: types[name] ?? nil)
            } catch {
                throw UndecodableProperty(property: name)
            }
        }
        return .map(entries)
    }

    /// `value` written as `type`.
    private func cbor(_ value: JSON, as type: WrittenType?) throws(Mismatch) -> CBOR {
        switch type?.shape {
        case .optional(let wrapped):
            guard value != .null else { return .null }
            return try cbor(value, as: wrapped)
        case .sensitive(let wrapped), .refined(let wrapped):
            return try cbor(value, as: wrapped)
        case .array(let element):
            guard case .array(let items) = value else { throw Mismatch() }
            var elements: [CBOR] = []
            elements.reserveCapacity(items.count)
            for item in items {
                elements.append(try cbor(item, as: element))
            }
            return .array(elements)
        case .date:
            guard case .string(let text) = value, let date = Date(iso8601Timestamp: text) else { throw Mismatch() }
            return .double(date.timeIntervalSinceReferenceDate)
        case .floatingPoint:
            // A Float too: the CBOR package reads a double as the nearest Float, which is the Float
            // the reader wrote by its shortest description.
            guard let number = value.double else { throw Mismatch() }
            return .double(number)
        case .other, nil:
            return anyValue(value)
        }
    }

    /// `value`, written for what it holds: a whole number as an integer.
    private func anyValue(_ value: JSON) -> CBOR {
        switch value {
        case .null:
            return .null
        case .boolean(let boolean):
            return .bool(boolean)
        case .string(let text):
            return .textString(text)
        case .integer(let integer):
            // CBOR writes a negative n as -1 - n, which is ~n in two's complement.
            return integer >= 0 ? .unsignedInt(UInt64(integer)) : .negativeInt(UInt64(~integer))
        case .number(let number):
            // A whole number past Int64, as the reader writes a UInt64 above Int64.max.
            return UInt64(exactly: number).map(CBOR.unsignedInt) ?? .double(number)
        case .array(let items):
            return .array(items.map(anyValue))
        case .object(let members):
            var entries: [CBOR: CBOR] = [:]
            for (name, item) in members {
                entries[.textString(name)] = anyValue(item)
            }
            return .map(entries)
        }
    }
}

/// A value that isn't one its type is written as.
private struct Mismatch: Error {}
