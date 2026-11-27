#if objectFormat(MachO)
    internal import MachO
#endif

/// The records `@Event` places in the binary so ``DiscoveredEvent/all`` can find every event
/// type a program links, and the code that reads them. An implementation detail of `@Event`:
/// don't use it directly.
///
/// A record has the layout of Swift Testing's test content records (`kind`, `reserved1`, an
/// accessor, `context`, `reserved2`; see swift-testing's `Documentation/ABI/TestContent.md`), in
/// a section of its own: `__DATA_CONST,__trfl_events` in Mach-O, `trfl_events` in ELF. Its
/// accessor writes a ``DiscoveredEvent`` to its first argument when the second points to
/// `DiscoveredEvent.self`, and returns whether it did.
// The section is the library's own, not Swift Testing's `swift5_tests`: these are production
// records, read without linking Testing or its `_TestDiscovery` module (a package only, behind
// `@_spi(Experimental)`), and Testing's walk of its section shouldn't meet them. The cost is ELF,
// where the Swift runtime registers only its own sections: there the linker's `__start_` and
// `__stop_` symbols bound this image's section alone, which is the whole program as SwiftPM and
// Bazel link Swift on Linux, statically.
public enum __EventDiscovery {
    /// A record's accessor: writes the record's ``DiscoveredEvent`` to `outValue` when `type`
    /// points to `DiscoveredEvent.self`, and returns whether it did. `hint` and `reserved` are
    /// unused.
    public typealias Accessor = @convention(c) (
        _ outValue: UnsafeMutableRawPointer,
        _ type: UnsafeRawPointer,
        _ hint: UnsafeRawPointer?,
        _ reserved: UInt
    ) -> Bool

    /// One record: `kind` is ``kind``, the other fields 0 but the accessor.
    // The accessor isn't optional, as Swift Testing's is: Swift 6.4 can't place an optional
    // function in a section.
    public typealias Record = (kind: UInt32, reserved1: UInt32, accessor: Accessor, context: UInt, reserved2: UInt)

    /// The kind of a record of an event type, `'evnt'` as a FourCC; a record of another kind is
    /// skipped.
    public static let kind: UInt32 = 0x6576_6E74

    /// Writes the event `type` with `schema` to `outValue`, when `expectedType` points to
    /// `DiscoveredEvent.self`, and returns whether it did; what a record's accessor calls.
    public static func load<E: Event & Codable>(
        _ type: E.Type,
        schema: @autoclosure () -> EventSchema,
        into outValue: UnsafeMutableRawPointer,
        ofType expectedType: UnsafeRawPointer
    ) -> Bool {
        // A second copy of this module in the process has a DiscoveredEvent of its own, whose
        // layout this one's needn't share, so only a reader asking for this module's type gets one.
        guard expectedType.load(as: Any.Type.self) == DiscoveredEvent.self else { return false }
        outValue.initializeMemory(as: DiscoveredEvent.self, repeating: DiscoveredEvent(type: type, schema: schema()), count: 1)
        return true
    }

    /// The event of each record in every image the process has loaded, in no particular order.
    static func events() -> [DiscoveredEvent] {
        sections().flatMap { section in
            section.withMemoryRebound(to: Record.self) { Array($0) }
        }
        .filter { $0.kind == kind }
        .compactMap(event(of:))
    }
}

// A record of kind 0, which readers skip, so the section exists in every program that links this
// module: an ELF linker defines `__start_` and `__stop_` symbols only for a section some object holds.
#if objectFormat(MachO)
    @section("__DATA_CONST,__trfl_events")
#elseif objectFormat(ELF)
    @section("trfl_events")
#endif
@used
private nonisolated let placeholderRecord: __EventDiscovery.Record = (0, 0, { _, _, _, _ in false }, 0, 0)

extension __EventDiscovery {
    /// The event `record`'s accessor writes, or `nil` when it writes none.
    fileprivate static func event(of record: Record) -> DiscoveredEvent? {
        withUnsafeTemporaryAllocation(of: DiscoveredEvent.self, capacity: 1) { buffer in
            withUnsafePointer(to: DiscoveredEvent.self as Any.Type) { expectedType in
                guard let outValue = buffer.baseAddress, record.accessor(outValue, expectedType, nil, 0) else { return nil }
                return outValue.move()
            }
        }
    }
}

#if objectFormat(MachO)
    extension __EventDiscovery {
        /// The event section of each image dyld has loaded, skipping the shared cache's system
        /// images, which declare no events.
        // Walked on each call rather than collected as images load, so an unloaded image's
        // section is never read later; an image loading or unloading during the walk itself is a
        // race dyld's API leaves open, as Swift Testing's fallback walk does.
        fileprivate static func sections() -> [UnsafeRawBufferPointer] {
            (0 ..< _dyld_image_count()).compactMap { index in
                guard let header = _dyld_get_image_header(index), header.pointee.flags & UInt32(MH_DYLIB_IN_CACHE) == 0 else { return nil }
                #if _pointerBitWidth(_64)
                    let image = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
                #else
                    let image = header
                #endif
                var size: UInt = 0
                guard let start = getsectiondata(image, "__DATA_CONST", "__trfl_events", &size), size > 0 else { return nil }
                return UnsafeRawBufferPointer(start: start, count: Int(clamping: size))
            }
        }
    }
#elseif objectFormat(ELF)
    /// A bound of the event section, whose address alone is used.
    private struct SectionBound: ~Copyable {
        private var storage: CChar = 0
    }

    @_silgen_name(raw: "__start_trfl_events") private nonisolated(unsafe) var sectionStart: SectionBound
    @_silgen_name(raw: "__stop_trfl_events") private nonisolated(unsafe) var sectionStop: SectionBound

    extension __EventDiscovery {
        /// The event section of the image holding this module.
        fileprivate static func sections() -> [UnsafeRawBufferPointer] {
            withUnsafeMutablePointer(to: &sectionStart) { start in
                withUnsafeMutablePointer(to: &sectionStop) { stop in
                    [UnsafeRawBufferPointer(start: start, count: UnsafeRawPointer(stop) - UnsafeRawPointer(start))]
                }
            }
        }
    }
#else
    extension __EventDiscovery {
        /// No sections: discovery reads Mach-O and ELF images only.
        fileprivate static func sections() -> [UnsafeRawBufferPointer] {
            []
        }
    }
#endif
