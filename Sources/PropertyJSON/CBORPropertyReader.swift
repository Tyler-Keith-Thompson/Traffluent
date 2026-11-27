internal import CBOR
import Foundation
internal import JSONValues
internal import TrackingPlans

/// Reads an event's CBOR, the map of its properties its `Encodable` conformance writes, as JSON,
/// guided by each property's type as its schema writes it.
///
/// The bytes alone don't say everything the JSON needs: a `Date` is a bare double of its seconds
/// since 2001 where `@Event` writes it, an optional's `nil` is left out, and a `Sensitive` value
/// a redacting encoding hides is `null`. The written type says which, as it does for the plan's
/// documents. Where there is none, the bytes are read for what they hold.
// Over the CBOR package's value tree rather than a Mirror of the event, which D7 rules out: it is
// slow, can't see optionality and can't reach a Sensitive value, whose mirror is empty.
struct CBORPropertyReader {
    /// Whether a `Sensitive` value was written as `null` in its place.
    private let redactsSensitiveValues: Bool

    /// A reader of an event's CBOR, written with its `Sensitive` values redacted when
    /// `redactsSensitiveValues` is set.
    init(redactsSensitiveValues: Bool) {
        self.redactsSensitiveValues = redactsSensitiveValues
    }

    /// The members of the map `bytes` hold, each read through its type in `types`; a redacted
    /// value is left out, and an optional property missing from the map is `null`.
    ///
    /// - Parameters:
    ///   - bytes: The event's CBOR.
    ///   - types: Each property's type as written; a missing or `nil` one is read for what the
    ///     bytes hold.
    ///   - event: The event's name, for the error.
    /// - Throws: ``PropertyReadingError/unrepresentableValue(event:property:)`` naming the
    ///   property whose value JSON can't hold, or the event's name for bytes that aren't a map
    ///   keyed by text.
    func properties(of bytes: [UInt8], types: [String: WrittenType?], event: String) throws(PropertyReadingError) -> [String: JSON] {
        guard let item = try? CBOR.decode(bytes), case .map(let entries) = item else {
            throw .unrepresentableValue(event: event, property: "")
        }
        var values: [(name: String, value: CBOR)] = []
        for (key, value) in entries {
            guard case .textString(let name) = key else { throw .unrepresentableValue(event: event, property: "") }
            values.append((name, value))
        }
        var members: [String: JSON] = [:]
        // By name, so of two properties JSON can't hold, the error always names the same one.
        for (name, value) in values.sorted(by: { $0.name < $1.name }) {
            do {
                members[name] = try json(value, as: types[name] ?? nil)
            } catch {
                throw .unrepresentableValue(event: event, property: name)
            }
        }
        // An optional property's nil is left out of the map; its JSON is null, as the plan's
        // documents allow.
        for (name, type) in types where entries[.textString(name)] == nil {
            if case .optional = type {
                members[name] = .null
            }
        }
        return members
    }

    /// `value` read as `type`, or `nil` for a redacted one.
    private func json(_ value: CBOR, as type: WrittenType?) throws(Unrepresentable) -> JSON? {
        switch type?.shape {
        case .optional(let wrapped):
            guard value.isNull else { return try json(value, as: wrapped) }
            // A redacted Sensitive value is null too: left out, as a redacted value is.
            if redactsSensitiveValues, case .sensitive = wrapped.shape { return nil }
            return .null
        case .sensitive(let wrapped):
            guard !redactsSensitiveValues else { return nil }
            return try json(value, as: wrapped)
        case .refined(let wrapped):
            return try json(value, as: wrapped)
        case .array(let element):
            guard case .array(let items) = value else { throw Unrepresentable() }
            var elements: [JSON] = []
            for item in items {
                elements.append(try json(item, as: element) ?? .null)
            }
            return .array(elements)
        case .date:
            return try .string(Self.date(value).iso8601Timestamp)
        case .other, nil:
            return try anyValue(value)
        }
    }

    /// `value`, read for what it holds.
    private func anyValue(_ value: CBOR) throws(Unrepresentable) -> JSON {
        switch value {
        case .null:
            return .null
        case .bool(let boolean):
            return .boolean(boolean)
        case .double(let number):
            return try .finite(number)
        case .float(let number):
            // Through its description, the shortest that reads back as the same Float, so 0.1 is
            // 0.1 rather than the Double nearest the Float, 0.10000000149011612. A Float's
            // description always parses as a Double, `nan` and `inf` included, which `finite`
            // rejects.
            guard let number = Double(number.description) else { throw Unrepresentable() }
            return try .finite(number)
        case .half:
            guard let number = value.doubleValue else { throw Unrepresentable() }
            return try .finite(number)
        case .unsignedInt(let magnitude):
            return Int64(exactly: magnitude).map(JSON.integer) ?? .number(Double(magnitude))
        case .negativeInt(let argument):
            // CBOR writes a negative n as -1 - n, which is ~n in two's complement.
            return Int64(exactly: argument).map { .integer(~$0) } ?? .number(-1 - Double(argument))
        case .textString(let text):
            return .string(text)
        case .array(let items):
            var elements: [JSON] = []
            for item in items {
                elements.append(try anyValue(item))
            }
            return .array(elements)
        case .map(let entries):
            var members: [String: JSON] = [:]
            for (key, item) in entries {
                guard case .textString(let name) = key else { throw Unrepresentable() }
                members[name] = try anyValue(item)
            }
            return .object(members)
        case .tagged(.epochDateTime, _):
            // A Date the CBOR package wrote itself: one inside an array or a type of the app's
            // own, which `@Event` doesn't reach.
            return try .string(Self.date(value).iso8601Timestamp)
        default:
            // Bytes, other tags and other simple values, undefined among them: JSON has no form
            // for them, and no standard type's encoding writes them.
            throw Unrepresentable()
        }
    }

    /// The date `value` holds: a bare double of its seconds since 2001, as `@Event` writes a
    /// `Date` property, or tag 1's seconds since 1970, as the CBOR package writes one it reaches
    /// itself.
    private static func date(_ value: CBOR) throws(Unrepresentable) -> Date {
        let date: Date
        switch value {
        case .double(let seconds):
            date = Date(timeIntervalSinceReferenceDate: seconds)
        case .tagged(.epochDateTime, .unsignedInt(let seconds)):
            date = Date(timeIntervalSince1970: Double(seconds))
        case .tagged(.epochDateTime, .negativeInt(let argument)):
            date = Date(timeIntervalSince1970: -1 - Double(argument))
        case .tagged(.epochDateTime, .double(let seconds)):
            date = Date(timeIntervalSince1970: seconds)
        default:
            throw Unrepresentable()
        }
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw Unrepresentable() }
        return date
    }
}

/// A value JSON has no form for, or bytes that don't hold the value their type says.
private struct Unrepresentable: Error {}

/// How a written type's value is read from its CBOR.
private enum Shape {
    /// `T?`, `T!` or `Optional<T>`: `null`, or `T`'s value.
    case optional(WrittenType)
    /// `Sensitive<T>`: `T`'s value, or `null` where it is redacted.
    case sensitive(WrittenType)
    /// `Refined<T, Rule>`, whose value is `T`'s.
    case refined(WrittenType)
    /// `[T]` or `Array<T>`.
    case array(WrittenType)
    /// `Date`: a double of its seconds since 2001, or tag 1's since 1970.
    case date
    /// Any other type, read for what its value holds.
    case other
}

extension WrittenType {
    /// How the type's value is read, with the module names the plan's documents accept.
    fileprivate var shape: Shape {
        if case .optional(let wrapped) = self { return .optional(wrapped) }
        if case .array(let element) = self { return .array(element) }
        if let arguments = names("Optional", in: ["Swift"]), arguments.count == 1 { return .optional(arguments[0]) }
        if let arguments = names("Array", in: ["Swift"]), arguments.count == 1 { return .array(arguments[0]) }
        if let arguments = names("Refined", in: ["Events", "Traffluent"]), arguments.count == 2 { return .refined(arguments[0]) }
        if let arguments = names("Sensitive", in: ["Events", "Traffluent"]), arguments.count == 1 { return .sensitive(arguments[0]) }
        if names("Date", in: ["Foundation", "FoundationEssentials"])?.isEmpty == true { return .date }
        return .other
    }
}

extension JSON {
    /// A finite number as JSON.
    ///
    /// - Throws: `Unrepresentable` for a NaN or an infinity, which JSON can't hold.
    fileprivate static func finite(_ number: Double) throws(Unrepresentable) -> JSON {
        guard let json = JSON.number(exactly: number) else { throw Unrepresentable() }
        return json
    }
}
