extension String {
    // Heap's track API reference (https://developers.heap.io/reference/track-1, read 2026-11-27):
    // the event "Limited to 1024 characters"; each property's key and value "a number or string
    // with fewer than 1024 characters"; "Do not use `user_id`, `session_id`, or `screen_name` as
    // keys inside the `properties` object". It doesn't say how it counts characters, so they are
    // counted as UTF-16 code units, JavaScript's `length`: never fewer than a count of Unicode
    // scalars or of grapheme clusters, so a name or value the encoder sends is within the limit
    // however Heap counts, short of counting bytes. Rejected: bytes, which would refuse a value of
    // 342 Chinese characters.

    /// Whether Heap takes the string as an event's name: at most 1,024 characters. An empty name
    /// never gets here, as no tracking plan holds one.
    var isHeapEventName: Bool {
        utf16.count <= 1_024
    }

    /// Whether the string is short enough for a property's key or value: fewer than 1,024
    /// characters.
    var fitsHeapProperty: Bool {
        utf16.count < 1_024
    }

    /// Whether the string is a property name Heap reserves: `user_id` and `session_id`, fields of a
    /// track request, and `screen_name`, which Heap's mobile SDKs capture.
    var isReservedByHeap: Bool {
        self == "user_id" || self == "session_id" || self == "screen_name"
    }
}
