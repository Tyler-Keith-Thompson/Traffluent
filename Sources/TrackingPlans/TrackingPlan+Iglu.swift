import Events
public import Foundation
import JSONValues

extension TrackingPlan {
    /// The plan's events as the schemas of an Iglu registry of the kind `registry` under `vendor`,
    /// one file per event and version: the newest Iglu version of each in `committed` while it
    /// still describes the event, or the one to publish next.
    ///
    /// Each file is at `schemas/<vendor>/<name>/jsonschema/<SchemaVer>`, the layout of an Iglu
    /// static repository, which `igluctl` publishes and Iglu Server takes. It holds the event's
    /// document as ``files`` writes it, as a self-describing schema: `$schema` is Iglu's
    /// self-describing meta-schema, `self` names the vendor, the event's name, the format
    /// `jsonschema` and the version, and `$id`, a file name of the plan's, is left out.
    ///
    /// Version N of an event is SchemaVer `N-0-0`, the version every event of it names: each
    /// version of an event is a breaking change, a SchemaVer MODEL. The newest version of the event
    /// in `committed`, `N-0-k`, is compared with the event by what the two mean, as
    /// ``check(against:)`` compares a plan, not by their bytes:
    ///
    /// - When nothing differs, the file returned is the committed one, byte for byte, however it
    ///   is formatted.
    /// - When a difference is breaking (``TrackingPlanDifference/isBreaking``), the export throws
    ///   ``IgluExportError/breakingChange(event:version:)``: a payload the published schema accepts
    ///   could fail the new one, which Iglu publishes only as a new MODEL, so raise the event's
    ///   version.
    /// - When every difference is compatible (an optional or defaulted property added, a property
    ///   removed, a constraint loosened), it is an ADDITION. For ``IgluRegistry/server`` the file
    ///   returned is `N-0-(k+1)`, which lists every earlier `N-0-*` in `$supersedes`, so Snowplow
    ///   validates events naming `N-0-0` against it; it keeps the properties of `N-0-k` the event
    ///   no longer declares, marked `deprecated` and not required, as ``files(carryingForward:)``
    ///   keeps them. A static repository doesn't supersede, so for
    ///   ``IgluRegistry/staticRepository`` the export throws
    ///   ``IgluExportError/additionNeedsNewVersion(event:version:)`` instead.
    ///
    /// - Parameters:
    ///   - vendor: The Iglu vendor of the app's schemas, in reverse domain notation
    ///     (`com.acme`), which the app's Snowplow destination is given too.
    ///   - registry: The kind of registry the files are published to.
    ///   - committed: The files of the registry exported before, with their paths from its root
    ///     (`schemas/…`). A file that isn't an Iglu version `N-0-k` of one of the plan's events at
    ///     the version N the plan lists is ignored.
    /// - Returns: One file per event of the plan, in the order of ``schemas``.
    /// - Throws: ``IgluExportError/invalidVendor`` for a vendor that isn't one;
    ///   ``IgluExportError/invalidSchemaKey(event:version:)`` for an event whose name Iglu doesn't
    ///   take or whose version is below 1; ``IgluExportError/allOf(event:version:)`` for a property
    ///   of more than one pattern; ``IgluExportError/breakingChange(event:version:)`` and
    ///   ``IgluExportError/additionNeedsNewVersion(event:version:)`` as above; and
    ///   ``IgluExportError/fileSystem(_:)`` with `CocoaError.fileReadCorruptFile` for a newest
    ///   committed version that isn't a schema the plan wrote.
    /// - Complexity: O(*n* log *n*) in the size of the plan and the registry.
    public func igluFiles(vendor: String, registry: IgluRegistry, carryingForward committed: [File]) throws(IgluExportError) -> [File] {
        guard vendor.isIgluVendor else { throw .invalidVendor }
        let committedFiles = Dictionary(committed.map { ($0.path, $0.contents) }) { first, _ in first }
        var files: [File] = []
        for schema in schemas {
            files.append(try schema.igluFile(vendor: vendor, registry: registry, committed: committedFiles))
        }
        return files
    }

    /// Writes the plan's events as the schemas of an Iglu registry of the kind `registry` under
    /// `vendor` into `directory`, the registry's root, creating the directories needed.
    ///
    /// The files are ``igluFiles(vendor:registry:carryingForward:)`` of the registry already in
    /// `directory`. Nothing there is deleted or changed: a version Iglu has published stays as it
    /// is, an event the plan no longer lists keeps its schemas, and a compatible change to an event
    /// writes a new version beside the earlier ones, for Iglu Server alone. Publish the new files
    /// (`igluctl static push` for Iglu Server, or a copy of `schemas/` for a static repository)
    /// before the release that sends the change.
    ///
    /// - Parameters:
    ///   - directory: The registry's root, which holds `schemas/`.
    ///   - vendor: The Iglu vendor of the app's schemas, in reverse domain notation (`com.acme`).
    ///   - registry: The kind of registry the files are published to.
    /// - Throws: The errors of ``igluFiles(vendor:registry:carryingForward:)``, and
    ///   ``IgluExportError/fileSystem(_:)`` with the `CocoaError` of the first schema already in
    ///   `directory` that couldn't be read, before anything is written, or of the first file that
    ///   couldn't be written, after the files before it.
    public func writeIgluRegistry(to directory: URL, vendor: String, registry: IgluRegistry) throws(IgluExportError) {
        let fileManager = FileManager.default
        let files = try igluFiles(vendor: vendor, registry: registry, carryingForward: igluRegistryFiles(in: directory, vendor: vendor))
        for file in files {
            let url = directory.appendingPathComponent(file.path)
            let contents = Data(file.contents)
            // A version already there comes back byte for byte; any other path is a new version.
            guard fileManager.contents(atPath: url.path) != contents else { continue }
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: url, options: .atomic)
            } catch {
                throw .fileSystem(CocoaError(error, path: url.path, otherwise: .fileWriteUnknown))
            }
        }
    }

    /// The files under `directory` of each version of the plan's events the registry holds, by
    /// their paths from `directory`: every file named as a SchemaVer in the folder of an event the
    /// plan lists. None for a vendor that isn't one or a folder that doesn't exist.
    ///
    /// - Throws: ``IgluExportError/fileSystem(_:)`` for a folder that can't be listed or a version
    ///   that can't be read, rather than leave it out: the export would then take its version for
    ///   unpublished and write over it.
    private func igluRegistryFiles(in directory: URL, vendor: String) throws(IgluExportError) -> [File] {
        guard vendor.isIgluVendor else { return [] }
        let fileManager = FileManager.default
        var files: [File] = []
        for name in Set(schemas.map(\.name)).filter(\.isIgluName).sorted() {
            let folder = EventSchema.igluFolder(vendor: vendor, name: name)
            let folderURL = directory.appendingPathComponent(folder)
            guard fileManager.fileExists(atPath: folderURL.path) else { continue }
            let entries: [String]
            do {
                entries = try fileManager.contentsOfDirectory(atPath: folderURL.path)
            } catch {
                throw .fileSystem(CocoaError(error, path: folderURL.path, otherwise: .fileReadUnknown))
            }
            for entry in entries.sorted() where entry.isSchemaVer {
                let url = folderURL.appendingPathComponent(entry)
                do {
                    files.append(File(path: folder + entry, contents: Array(try Data(contentsOf: url))))
                } catch {
                    throw .fileSystem(CocoaError(error, path: url.path, otherwise: .fileReadUnknown))
                }
            }
        }
        return files
    }
}

extension EventSchema {
    /// The registry's folder of the event `name`'s schemas under `vendor`, ending in `/`.
    fileprivate static func igluFolder(vendor: String, name: String) -> String {
        "schemas/\(vendor)/\(name)/jsonschema/"
    }

    /// The event's Iglu schema file: the newest version of it in `committed` while it still
    /// describes the event, or the next addition for Iglu Server.
    fileprivate func igluFile(vendor: String, registry: IgluRegistry, committed: [String: [UInt8]]) throws(IgluExportError) -> TrackingPlan.File {
        guard name.hasIgluSchemaKey(version: version) else { throw .invalidSchemaKey(event: name, version: version) }
        let folder = Self.igluFolder(vendor: vendor, name: name)
        let prefix = folder + String.igluSchemaVersion(model: version, addition: 0).dropLast()
        // The additions of this version the registry holds, `N-0-k`, in canonical decimal, below
        // Int.max so the next one can't overflow.
        let additions = committed.keys.compactMap { path -> Int? in
            guard path.hasPrefix(prefix) else { return nil }
            let digits = path.dropFirst(prefix.count)
            guard let addition = Int(digits), addition < .max, String(addition) == digits else { return nil }
            return addition
        }
        guard let latest = additions.max() else {
            return try igluFile(vendor: vendor, addition: 0, keepingRemovedFrom: nil)
        }
        let latestPath = folder + String.igluSchemaVersion(model: version, addition: latest)
        let latestBytes = committed[latestPath] ?? []
        // Compared by meaning, as the plan's own check compares it, so a file reformatted since
        // (another indentation, CRLF line endings) is still the published version.
        guard let latestDocument = JSON(parsing: latestBytes), let differences = differences(fromCommitted: latestDocument) else {
            throw .fileSystem(CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: latestPath]))
        }
        if differences.isEmpty {
            return TrackingPlan.File(path: latestPath, contents: latestBytes)
        }
        if differences.contains(where: \.isBreaking) {
            throw .breakingChange(event: name, version: version)
        }
        switch registry {
        case .server: return try igluFile(vendor: vendor, addition: latest + 1, keepingRemovedFrom: latestDocument)
        // Rejected: writing the addition with a warning. A static repository serves N-0-0 to
        // events naming it whatever else is there, so they would fail on what changed, silently.
        case .staticRepository: throw .additionNeedsNewVersion(event: name, version: version)
        }
    }

    /// The event's schema as Iglu version `<version>-0-<addition>` under `vendor`, superseding
    /// each earlier addition, keeping the properties of `committed` it no longer declares.
    private func igluFile(vendor: String, addition: Int, keepingRemovedFrom committed: JSON?) throws(IgluExportError) -> TrackingPlan.File {
        var members = document(keepingRemovedFrom: committed).object ?? [:]
        // Snowplow's JSON Schema reference lists allOf among what its validation doesn't support,
        // so a document needing it is refused rather than published and then not enforced. The
        // plan writes allOf only at the top of a property's schema (a second pattern), and a
        // property kept from a committed file has the schema the plan wrote then; the properties'
        // own names aren't searched, as a property may be named `allOf`.
        if members["properties"]?.object?.values.contains(where: { $0.object?["allOf"] != nil }) == true {
            throw .allOf(event: name, version: version)
        }
        let schemaVersion = String.igluSchemaVersion(model: version, addition: addition)
        // $id names the plan's file; a self-describing schema names itself in `self` instead. The
        // plan's own keywords (`x-traffluent-*`, `deprecated`, `examples`) stay: Iglu Server
        // refuses a schema only for errors, and Schema DDL reports a keyword draft 4 doesn't know
        // as a warning at most (SelfSyntaxChecker's strict check, schema-ddl 0.27.0).
        members["$id"] = nil
        members["$schema"] = .string("http://iglucentral.com/schemas/com.snowplowanalytics.self-desc/schema/jsonschema/1-0-0#")
        members["self"] = .object([
            "vendor": .string(vendor),
            "name": .string(name),
            "format": .string("jsonschema"),
            "version": .string(schemaVersion),
        ])
        if addition > 0 {
            members["$supersedes"] = .array((0..<addition).map { .string(String.igluSchemaVersion(model: version, addition: $0)) })
        }
        return TrackingPlan.File(path: Self.igluFolder(vendor: vendor, name: name) + schemaVersion, json: .object(members))
    }
}

extension String {
    /// Whether the string is a SchemaVer: three numbers in canonical decimal, joined by `-`.
    fileprivate var isSchemaVer: Bool {
        let parts = split(separator: "-", omittingEmptySubsequences: false)
        // Split on `-`, no part holds a sign, so canonical decimal is a number of 0 or more.
        return parts.count == 3 && parts.allSatisfy { part in Int(part).map { String($0) == part } ?? false }
    }
}

extension CocoaError {
    /// `error` as the `CocoaError` Foundation's file APIs throw, or `code` for `path` when it is
    /// another error.
    fileprivate init(_ error: any Error, path: String, otherwise code: CocoaError.Code) {
        self = (error as? CocoaError) ?? CocoaError(code, userInfo: [NSFilePathErrorKey: path])
    }
}
