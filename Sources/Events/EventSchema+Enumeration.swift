extension EventSchema {
    /// The raw values a property of a raw-value enum is written as: the enum's name, its raw value's
    /// type and, where they are known, every case's raw value.
    ///
    /// `@Event` gives a property one when its type is an enum whose raw value is a `String` or a
    /// standard integer type (`Int`, `UInt8`, ...), also through `Optional`, `Sensitive` and arrays,
    /// and its cases are known: the enum is declared inside the event, where the macro lists the
    /// cases it declares, or conforms to `CaseIterable`. An enum declared elsewhere that isn't
    /// `CaseIterable` has none, and a tracking plan accepts any value for it:
    ///
    /// ```swift
    /// @Event
    /// struct CheckoutFailed {
    ///     enum Reason: String, Codable {
    ///         case paymentDeclined
    ///         case outOfStock
    ///     }
    ///     var reason: Reason
    /// }
    ///
    /// CheckoutFailed.schema.properties[0].enumeration?.rawValues
    /// // [.string("paymentDeclined"), .string("outOfStock")]
    /// ```
    ///
    /// A tracking plan writes such a property as its raw value's type, with a JSON Schema `enum` of
    /// the raw values.
    public struct Enumeration: Sendable, Hashable {
        /// One case's raw value.
        public enum RawValue: Sendable, Hashable {
            /// A `String` raw value.
            case string(String)
            /// An integer raw value.
            case integer(Int64)
        }

        /// The enum's name, as Swift describes the type: `Reason` for `CheckoutFailed.Reason`.
        public let typeName: String
        /// The type of the enum's raw value, as Swift describes it: `String`, `Int`.
        public let rawTypeName: String
        /// Each case's raw value, in the order given, each once; `nil` when no case was given, or
        /// one is an integer outside `Int64`'s range.
        public let rawValues: [RawValue]?

        /// The raw values of `cases`, an enum's cases, or `nil` when its raw value is neither a
        /// `String` nor a standard integer type.
        ///
        /// - Parameter cases: The enum's cases, in declaration order: `Reason.allCases`, or each
        ///   case written out. Given none, the raw values are unknown.
        /// - Complexity: O(*n*) in the number of cases.
        public init?<Case: RawRepresentable>(cases: [Case]) {
            guard Enumeration.mapsRawValue(of: Case.self) else { return nil }
            typeName = String(describing: Case.self)
            rawTypeName = String(describing: Case.RawValue.self)
            // Nil only for a UInt or UInt64 above Int64.max, which leaves the cases unknown.
            let converted = cases.map { RawValue($0.rawValue) }
            var seen = Set<RawValue>()
            let values = converted.compactMap { $0 }.filter { seen.insert($0).inserted }
            rawValues = values.isEmpty || converted.contains(nil) ? nil : values
        }

        /// The raw values of the type at `keyPath`, looked through `Optional`, `Sensitive` and
        /// arrays, or `nil` unless that type is `CaseIterable` and `RawRepresentable` with a
        /// `String` or standard integer raw value, and every case's raw value is known.
        ///
        /// A type that isn't `CaseIterable` has none, even when it is `RawRepresentable`: its
        /// `Codable` conformance may be its own rather than its raw value's, so a plan can't say
        /// which values it writes.
        ///
        /// `@Event` reads a property's enumeration through this, unless the enum is declared inside
        /// the event, where it lists the cases itself.
        ///
        /// - Parameter keyPath: A property of an event.
        public init?<Root, Value>(of keyPath: KeyPath<Root, Value>) {
            guard let enumeration = Enumeration.enumeration(of: Value.self) else { return nil }
            self = enumeration
        }

        /// Whether `Case`'s raw value is a `String` or a standard integer type, which a plan maps.
        private static func mapsRawValue<Case: RawRepresentable>(of _: Case.Type) -> Bool {
            let rawTypes: [Any.Type] = [
                String.self, Int.self, Int8.self, Int16.self, Int32.self, Int64.self, UInt.self, UInt8.self, UInt16.self, UInt32.self, UInt64.self,
            ]
            return rawTypes.contains { $0 == Case.RawValue.self }
        }

        /// The enumeration of `type`, looked through the wrappers whose JSON is their value's.
        private static func enumeration(of type: Any.Type) -> Enumeration? {
            if let wrapper = type as? any EnumerationWrapper.Type {
                return enumeration(of: wrapper.wrappedType)
            }
            if let iterable = type as? any (RawRepresentable & CaseIterable).Type {
                return listing(iterable)
            }
            return nil
        }

        /// The enumeration of every case of `Case`, or `nil` when their raw values aren't all known.
        private static func listing<Case: RawRepresentable & CaseIterable>(_ type: Case.Type) -> Enumeration? {
            Enumeration(cases: Array(Case.allCases)).flatMap { $0.rawValues == nil ? nil : $0 }
        }
    }
}

extension EventSchema.Enumeration.RawValue {
    /// `value` as a raw value: a `String`'s, or an integer's within `Int64`'s range.
    fileprivate init?(_ value: Any) {
        if let string = value as? String {
            self = .string(string)
        } else if let integer = value as? any BinaryInteger, let exact = Int64(exactly: integer) {
            self = .integer(exact)
        } else {
            return nil
        }
    }
}
