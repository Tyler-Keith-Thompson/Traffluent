import Foundation
import SystemPackage

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

// swift-system has no fsync, unlink or directory listing, so these call the C library, and
// Foundation for directories, on every platform the store builds for.

/// An open segment file, closed when the last reference to it goes.
///
/// A class so that a synchronization running outside the store's lock keeps the descriptor open
/// even if the segment is deleted meanwhile; its number can't be reused for another file until then.
final class SegmentFile: Sendable {
    let path: FilePath
    let descriptor: FileDescriptor

    init(path: FilePath, descriptor: FileDescriptor) {
        self.path = path
        self.descriptor = descriptor
    }

    deinit {
        try? descriptor.close()
    }
}

/// Runs `body`, which throws swift-system's untyped errors, as throwing `Errno`.
@discardableResult
func withErrno<Result>(_ body: () throws -> Result) throws(Errno) -> Result {
    do {
        return try body()
    } catch let error as Errno {
        throw error
    } catch {
        throw Errno.ioError
    }
}

extension FileDescriptor {
    /// Flushes the file's written bytes to storage (`fsync`).
    ///
    /// `fsync` rather than Darwin's `F_FULLFSYNC`, which also flushes the drive's cache at many
    /// times the cost: losing the last moments of analytics to a power cut is acceptable.
    func synchronize() throws(Errno) {
        guard fsync(rawValue) == 0 else { throw Errno(rawValue: errno) }
    }

    /// Writes every byte of `bytes`, retrying after an interruption.
    ///
    /// Rather than swift-system's `writeAll`, which is generic over its sequence and isn't
    /// specialized across the module boundary: a write per record pays for that.
    func writeAll(_ bytes: UnsafeRawBufferPointer) throws(Errno) {
        var written = 0
        while written < bytes.count {
            written += try withErrno { try write(UnsafeRawBufferPointer(rebasing: bytes[written...])) }
        }
    }

    /// Every byte of the file, from its start.
    func readAll() throws(Errno) -> [UInt8] {
        try withErrno {
            let size = Int(try seek(offset: 0, from: .end))
            try seek(offset: 0, from: .start)
            var bytes = [UInt8](repeating: 0, count: size)
            let count = try bytes.withUnsafeMutableBytes { buffer in
                var count = 0
                while count < size {
                    let read = try self.read(into: UnsafeMutableRawBufferPointer(rebasing: buffer[count...]))
                    guard read > 0 else { break }
                    count += read
                }
                return count
            }
            bytes.removeLast(size - count)
            return bytes
        }
    }
}

extension FilePath {
    /// Flushes the directory at this path to storage, so the files created in it survive a power
    /// loss: on Linux a file's own `fsync` doesn't make its directory entry durable.
    func synchronizeDirectory() throws(Errno) {
        let descriptor = try withErrno { try FileDescriptor.open(self, .readOnly) }
        defer { try? descriptor.close() }
        try descriptor.synchronize()
    }

    /// Deletes the file at this path.
    func removeFile() throws(Errno) {
        let result = withPlatformString { unlink($0) }
        guard result == 0 else { throw Errno(rawValue: errno) }
    }

    /// Renames the file at this path to `destination`, replacing any file there in one step
    /// (`rename`).
    func rename(to destination: FilePath) throws(Errno) {
        let result = withPlatformString { source in
            destination.withPlatformString { renameFile(source, $0) }
        }
        guard result == 0 else { throw Errno(rawValue: errno) }
    }

    /// Creates the directory at this path and any missing parents, with the store's protection
    /// on Apple platforms; does nothing to one that exists but apply that protection.
    func createDirectory() throws(Errno) {
        let url = URL(fileURLWithPath: string, isDirectory: true)
        do {
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            // Files created in the directory take its protection class, so segments stay
            // readable while the device is locked after its first unlock, when background
            // deliveries run.
            let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
            try FileManager.default.setAttributes(attributes, ofItemAtPath: string)
            #else
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            #endif
            #if canImport(Darwin)
            // Unsent analytics are no use restored onto another device.
            var excluded = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            #endif
        } catch {
            throw Errno(posixErrorIn: error)
        }
    }

    /// The names of the entries in the directory at this path.
    func directoryEntries() throws(Errno) -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: string)
        } catch {
            throw Errno(posixErrorIn: error)
        }
    }
}

/// The C library's `rename`, under a name `FilePath.rename(to:)` doesn't shadow.
private func renameFile(_ source: UnsafePointer<CChar>, _ destination: UnsafePointer<CChar>) -> CInt {
    rename(source, destination)
}

extension Errno {
    /// The POSIX error under Foundation's `error`, or an I/O error when it has none.
    fileprivate init(posixErrorIn error: any Error) {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain {
            self.init(rawValue: CInt(truncatingIfNeeded: error.code))
        } else if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            self.init(rawValue: CInt(truncatingIfNeeded: underlying.code))
        } else {
            self = .ioError
        }
    }
}
