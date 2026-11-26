/// A CBOR data item's major type (RFC 8949, section 3.1): the top three bits of its first byte.
@usableFromInline
package enum BinaryMajorType: UInt8 {
    case unsignedInteger = 0
    case negativeInteger = 1
    case byteString = 2
    case textString = 3
    case array = 4
    case map = 5
    case tag = 6
    case simpleOrFloat = 7

    /// The major type a head's first byte, `initial`, names in its top three bits, each of whose
    /// eight values names one.
    @inlinable
    package init(initial: UInt8) {
        switch initial >> 5 {
        case 0: self = .unsignedInteger
        case 1: self = .negativeInteger
        case 2: self = .byteString
        case 3: self = .textString
        case 4: self = .array
        case 5: self = .map
        case 6: self = .tag
        default: self = .simpleOrFloat
        }
    }

    /// The first byte of a head of this type, before its additional information.
    @inlinable
    package var initialByte: UInt8 {
        rawValue << 5
    }
}
