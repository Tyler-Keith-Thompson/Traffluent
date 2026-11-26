// The example of the Checksums module's landing article
// (Sources/Checksums/Checksums.docc/Checksums.md), verbatim, so the article cannot drift from the
// code.

import Foundation
import Testing
import Traffluent

@Suite("Checksums module examples", .timeLimit(.minutes(1)))
struct ChecksumsModuleExamplesTests {
    @Test("A checksum fed in pieces equals the checksum of the whole")
    func checksumInPieces() {
        let header = Data("TRAF".utf8)
        let payload = Data("123456789".utf8)
        var crc = CRC32()
        header.withUnsafeBytes { crc.update(with: $0) }
        payload.withUnsafeBytes { crc.update(with: $0) }
        let whole = (header + payload).withUnsafeBytes { CRC32.checksum(of: $0) }
        let matches = crc.checksum == whole  // true

        let expectedCheckValue: UInt32 = 0xCBF4_3926
        let actualCheckValue = payload.withUnsafeBytes { CRC32.checksum(of: $0) }
        #expect(matches)
        #expect(actualCheckValue == expectedCheckValue)
    }
}
