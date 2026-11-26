import Events

extension TrackingPlan {
    /// A committed document of an earlier version of one of the plan's events, with its example
    /// when there is one, which the plan's files keep byte for byte: releases still installed send
    /// that version, and a record carries no version for a validator to pick a document by.
    struct EarlierVersion {
        let name: String
        let version: Int
        let document: File
        let example: File?

        /// The version's entry in the index, or `nil` when its document isn't one of this event at
        /// this version, which a validator loading the index couldn't read: such a document is kept,
        /// but not listed.
        var indexEntry: JSON? {
            guard let members = JSON(parsing: document.contents)?.object,
                members["title"]?.string == name,
                members["x-traffluent-version"]?.integer == Int64(version),
                let consentCategory = members["x-traffluent-consent-category"]?.string
            else { return nil }
            var entry: [String: JSON] = [
                "name": .string(name),
                "version": .integer(Int64(version)),
                "consentCategory": .string(consentCategory),
                "schema": .string(document.path),
            ]
            entry["example"] = example.map { .string($0.path) }
            return .object(entry)
        }

        var files: [File] {
            [document] + (example.map { [$0] } ?? [])
        }
    }

    /// The documents in `committed` of each event the plan lists, at a version below the newest
    /// it lists and that it doesn't list itself, in no particular order.
    ///
    /// A version is found by its document's file name, `<name>.v<version>.schema.json`; an example
    /// without its document is no earlier version. Documents at a version above the newest are
    /// not kept: versions only rise from release to release, so one above the plan's never
    /// shipped from this history (a version lowered before release, or another branch's file),
    /// and a validator holding it would accept payloads no release sends.
    ///
    /// - Parameter committed: The bytes of a plan exported before, by path.
    /// - Complexity: O(*e* × *f*) for *e* events in the plan and *f* committed files.
    func earlierVersions(in committed: [String: [UInt8]]) -> [EarlierVersion] {
        // Unique by name: the schemas are sorted by name, so one event's versions are neighbours.
        var versionsByName: [(name: String, versions: Set<Int>)] = []
        for schema in schemas {
            if versionsByName.last?.name == schema.name {
                versionsByName[versionsByName.count - 1].versions.insert(schema.version)
            } else {
                versionsByName.append((schema.name, [schema.version]))
            }
        }
        return versionsByName.flatMap { name, versions in
            let stem = EventSchema.encodedFileName(of: name) + ".v"
            let newest = versions.max() ?? Int.min
            return committed.compactMap { path, contents -> EarlierVersion? in
                guard let version = Self.version(inDocumentPath: path, stem: stem), version < newest, !versions.contains(version) else { return nil }
                let examplePath = "\(stem)\(version).example.json"
                return EarlierVersion(
                    name: name,
                    version: version,
                    document: File(path: path, contents: contents),
                    example: committed[examplePath].map { File(path: examplePath, contents: $0) }
                )
            }
        }
    }

    /// The version in `path`, when it is the document file name `<stem><version>.schema.json`
    /// with the version written as a plan writes it.
    private static func version(inDocumentPath path: String, stem: String) -> Int? {
        let suffix = ".schema.json"
        guard path.hasPrefix(stem), path.hasSuffix(suffix) else { return nil }
        let digits = path.dropFirst(stem.count).dropLast(suffix.count)
        // `Int` reads "+1" and "01" as 1, which a plan never writes, so those are another file.
        return Int(digits).flatMap { String($0) == digits ? $0 : nil }
    }
}
