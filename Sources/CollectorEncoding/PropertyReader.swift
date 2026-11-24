import Foundation
import Persistence
import TrackingPlans

/// Reads an event's `BinaryCodable` bytes, a CBOR map of its properties, as JSON, guided by each
/// property's type as its schema writes it.
///
/// The bytes alone don't say everything the JSON needs: a `Date` is a bare double of its seconds,
/// and an optional's value may sit in a one-element array that marks it apart from `nil`. The
/// written type says which, as it does for the plan's documents. Where there is none, the bytes are
/// read for what they hold.
// Over the bytes rather than a Mirror of the event, which D7 rules out: it is slow, can't see
// optionality and can't reach a Sensitive value, whose mirror is empty.
struct PropertyReader {
    private var decoder: BinaryDecoder

    /// A reader of `bytes`, from their start.
    init(bytes: [UInt8]) {
        decoder = BinaryDecoder(bytes)
    }

    /// The members of the map the bytes start with, each read through its type in `types`;
    /// a redacted value is left out.
    ///
    /// - Parameters:
    ///   - types: Each property's type as written; a missing or `nil` one is read for what the
    ///     bytes hold.
    ///   - event: The event's name, for the error.
    /// - Throws: ``CollectorEncodingError/unrepresentableValue(event:property:)`` naming the
    ///   property whose bytes JSON can't hold, or the event's name for bytes that aren't a map.
    mutating func properties(types: [String: WrittenType?], event: String) throws(CollectorEncodingError) -> [String: JSON] {
        let count: Int
        do {
            count = try decoder.readCount(of: .map, elementSize: 2)
        } catch {
            throw .unrepresentableValue(event: event, property: "")
        }
        var members: [String: JSON] = [:]
        for _ in 0 ..< count {
            let key: String
            do {
                key = try decoder.readText()
            } catch {
                throw .unrepresentableValue(event: event, property: "")
            }
            do {
                members[key] = try value(of: types[key] ?? nil)
            } catch {
                throw .unrepresentableValue(event: event, property: key)
            }
        }
        return members
    }

    /// The next value, read as `type`, or `nil` for a redacted one.
    private mutating func value(of type: WrittenType?) throws(BinaryDecodingError) -> JSON? {
        if decoder.peek() == BinarySimpleValue.undefined {
            _ = try decoder.readByte()
            return nil
        }
        switch type?.shape {
        case .optional(let wrapped):
            switch decoder.peek() {
            case BinarySimpleValue.null:
                _ = try decoder.readByte()
                return .null
            case Bool?.wrapperHead:
                // The same head for every wrapped type: a value whose own bytes start with null or
                // with this head, kept apart from nil.
                _ = try decoder.readByte()
                return try value(of: wrapped)
            default:
                return try value(of: wrapped)
            }
        case .value(let wrapped):
            return try value(of: wrapped)
        case .array(let element):
            let count = try decoder.readCount(of: .array)
            var elements: [JSON] = []
            for _ in 0 ..< count {
                elements.append(try value(of: element) ?? .null)
            }
            return .array(elements)
        case .date:
            let seconds = try decoder.decode(Double.self)
            guard seconds.isFinite else { throw .invalidValue }
            return .string(Date(timeIntervalSinceReferenceDate: seconds).collectorTimestamp)
        case .other, nil:
            return try anyValue()
        }
    }

    /// The next value, read for what its bytes hold, or `nil` for a redacted one.
    private mutating func anyValue() throws(BinaryDecodingError) -> JSON? {
        switch decoder.peek() {
        case BinarySimpleValue.undefined:
            _ = try decoder.readByte()
            return nil
        case BinarySimpleValue.null:
            _ = try decoder.readByte()
            return .null
        case BinarySimpleValue.false:
            _ = try decoder.readByte()
            return .boolean(false)
        case BinarySimpleValue.true:
            _ = try decoder.readByte()
            return .boolean(true)
        case BinarySimpleValue.float64:
            return try .finite(decoder.decode(Double.self))
        case BinarySimpleValue.float32:
            let number = try decoder.decode(Float.self)
            // Through its description, the shortest that reads back as the same Float, so 0.1 is
            // 0.1 rather than the Double nearest the Float, 0.10000000149011612. A Float's
            // description always parses as a Double, `nan` and `inf` included, which `finite`
            // rejects.
            return try .finite(Double(number.description)!)
        default:
            break
        }
        let head = try decoder.readHead()
        switch head.majorType {
        case .unsignedInteger:
            return Int64(exactly: head.argument).map(JSON.integer) ?? .number(Double(head.argument))
        case .negativeInteger:
            // CBOR writes a negative n as -1 - n, which is ~n in two's complement.
            return Int64(exactly: head.argument).map { .integer(~$0) } ?? .number(-1 - Double(head.argument))
        case .textString:
            let utf8 = try decoder.read(decoder.count(head.argument, elementSize: 1))
            guard let text = String(validating: utf8, as: UTF8.self) else { throw .invalidValue }
            return .string(text)
        case .array:
            var elements: [JSON] = []
            for _ in 0 ..< (try decoder.count(head.argument, elementSize: 1)) {
                elements.append(try anyValue() ?? .null)
            }
            return .array(elements)
        case .map:
            var members: [String: JSON] = [:]
            for _ in 0 ..< (try decoder.count(head.argument, elementSize: 2)) {
                let key = try decoder.readText()
                members[key] = try anyValue()
            }
            return .object(members)
        case .tag where head.argument == UUID.cborTag:
            guard try decoder.readCount(of: .byteString) == 16 else { throw .invalidValue }
            let bytes = try decoder.read(16)
            var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            withUnsafeMutableBytes(of: &uuid) { $0.copyBytes(from: bytes) }
            return .string(UUID(uuid: uuid).uuidString)
        case .byteString, .tag, .simpleOrFloat:
            // Bytes, other tags and other simple values: JSON has no form for them, and no
            // standard type's encoding writes them.
            throw .invalidValue
        }
    }
}

/// How a written type's value is read from its bytes.
private enum Shape {
    /// `T?`, `T!` or `Optional<T>`: `null`, or `T`'s value.
    case optional(WrittenType)
    /// `Refined<T, Rule>` or `Sensitive<T>`, whose bytes are `T`'s.
    case value(WrittenType)
    /// `[T]` or `Array<T>`.
    case array(WrittenType)
    /// `Date`, whose bytes are a double of its seconds since 2001.
    case date
    /// Any other type, read for what its bytes hold.
    case other
}

extension WrittenType {
    /// How the type's value is read, with the module names the plan's documents accept.
    fileprivate var shape: Shape {
        if case .optional(let wrapped) = self { return .optional(wrapped) }
        if case .array(let element) = self { return .array(element) }
        if let arguments = names("Optional", in: ["Swift"]), arguments.count == 1 { return .optional(arguments[0]) }
        if let arguments = names("Array", in: ["Swift"]), arguments.count == 1 { return .array(arguments[0]) }
        if let arguments = names("Refined", in: ["Events", "Traffluent"]), arguments.count == 2 { return .value(arguments[0]) }
        if let arguments = names("Sensitive", in: ["Events", "Traffluent"]), arguments.count == 1 { return .value(arguments[0]) }
        if names("Date", in: ["Foundation", "FoundationEssentials"])?.isEmpty == true { return .date }
        return .other
    }
}

extension JSON {
    /// A finite number as JSON.
    ///
    /// - Throws: ``BinaryDecodingError/invalidValue`` for a NaN or an infinity, which JSON can't
    ///   hold.
    fileprivate static func finite(_ number: Double) throws(BinaryDecodingError) -> JSON {
        guard number.isFinite else { throw .invalidValue }
        return .number(exactly: number)
    }
}

extension BinaryDecoder {
    /// Reads a text string: a map's key.
    fileprivate mutating func readText() throws(BinaryDecodingError) -> String {
        let utf8 = try read(readCount(of: .textString))
        guard let text = String(validating: utf8, as: UTF8.self) else { throw .invalidValue }
        return text
    }
}
