/// A CBOR data item's head (RFC 8949, section 3): its major type and argument.
@usableFromInline
struct DataItemHead {
    /// What the item is: an integer, a string, an array, a map, a tag or a simple value.
    @usableFromInline let majorType: BinaryMajorType
    /// The integer, the length or count, the tag number, or the simple value.
    @usableFromInline let argument: UInt64

    @inlinable
    init(majorType: BinaryMajorType, argument: UInt64) {
        self.majorType = majorType
        self.argument = argument
    }
}
