import Foundation
import LifecycleTracking
import SystemPackage
import Testing

@Suite("FileVersionStore")
struct FileVersionStoreTests {
    @Test("A directory without the file holds no version")
    func missing() throws {
        let directory = FilePath(FileManager.default.temporaryDirectory.appending(path: "FileVersionStore-\(UUID().uuidString)").path(percentEncoded: false))
        let sut = FileVersionStore(directory: directory)

        let actual = try sut.load()

        #expect(actual == nil)
    }

    @Test("A saved version loads back, from a directory the save created with its parents, in a file named version")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FileVersionStore-\(UUID().uuidString)").path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let directory = FilePath(root).appending("nested")
        let sut = FileVersionStore(directory: directory)
        let expected = "1.2.0"

        try sut.save(expected)
        let actual = try FileVersionStore(directory: directory).load()

        #expect(actual == expected)
        #expect(sut.file == directory.appending("version"))
        #expect(FileManager.default.fileExists(atPath: directory.appending("version").string))
    }

    @Test("A second save replaces the first")
    func replaced() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FileVersionStore-\(UUID().uuidString)").path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let sut = FileVersionStore(directory: FilePath(root))
        let expected = "2.0"

        try sut.save("1.0.0-beta")
        try sut.save(expected)
        let actual = try sut.load()

        #expect(actual == expected)
    }

    @Test("A file that can't be read throws rather than reading as no version")
    func unreadable() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FileVersionStore-\(UUID().uuidString)").path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(atPath: root) }
        // A directory where the file should be: it exists, and can't be read as one.
        try FileManager.default.createDirectory(atPath: root + "/version", withIntermediateDirectories: true)
        let sut = FileVersionStore(directory: FilePath(root))

        #expect(throws: (any Error).self) {
            try sut.load()
        }
    }

    @Test("The in-memory store's copies share the version it saves")
    func inMemoryShared() {
        let sut = InMemoryVersionStore(version: "1.0")
        let copy = sut

        copy.save("1.1")

        #expect(sut.version == "1.1")
        #expect(sut.load() == "1.1")
    }
}
