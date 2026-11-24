/// The CBOR first bytes the encoding writes whole: the simple values and the floats' heads.
@usableFromInline
package enum BinarySimpleValue {
    @usableFromInline package static let `false`: UInt8 = 0xF4
    @usableFromInline package static let `true`: UInt8 = 0xF5
    @usableFromInline package static let null: UInt8 = 0xF6
    @usableFromInline package static let undefined: UInt8 = 0xF7
    @usableFromInline package static let float32: UInt8 = 0xFA
    @usableFromInline package static let float64: UInt8 = 0xFB
}
