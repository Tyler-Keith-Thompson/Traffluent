extension String {
    // From Aptabase's server, github.com/aptabase/aptabase at 89d36185 (read 2026-11-27),
    // src/Features/Ingestion/EventBody.cs: EventName is [Required, StringLength(60)], which the
    // controller's model validation checks, answering 400 for the whole request; IsValid drops an
    // event whose property key IsNullOrWhiteSpace or is over 40 characters, answering 200;
    // SplitProps cuts a string value over 180 characters to 177 and "..."
    // (src/Extensions/StringExtensions.cs). .NET counts a string's length in UTF-16 code units,
    // and its whitespace (Char.IsWhiteSpace) is Unicode's White_Space property.

    /// Whether Aptabase takes the string as an event's name: not empty or only whitespace, and at
    /// most 60 characters.
    var isAptabaseEventName: Bool {
        !isBlank && utf16.count <= 60
    }

    /// Whether the string is empty or only whitespace, as .NET's `IsNullOrWhiteSpace` says.
    var isBlank: Bool {
        unicodeScalars.allSatisfy(\.properties.isWhitespace)
    }

    /// Whether the string is short enough for a property's name: at most 40 characters.
    var fitsAptabasePropertyName: Bool {
        utf16.count <= 40
    }

    /// Whether Aptabase stores the string as a property's value as it is: at most 180 characters.
    var fitsAptabasePropertyValue: Bool {
        utf16.count <= 180
    }
}
