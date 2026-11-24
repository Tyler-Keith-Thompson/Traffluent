/// A CBOR data item's major type (RFC 8949, section 3.1): the top three bits of its first byte.
@usableFromInline
enum BinaryMajorType: UInt8 {
    case unsignedInteger = 0
    case negativeInteger = 1
    case byteString = 2
    case textString = 3
    case array = 4
    case map = 5
    case tag = 6
    case simpleOrFloat = 7

    /// The first byte of a head of this type, before its additional information.
    @inlinable
    var initialByte: UInt8 {
        rawValue << 5
    }
}
