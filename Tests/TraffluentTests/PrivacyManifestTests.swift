// The published package's privacy manifests (RESOURCES in scripts/modules.py): SwiftPM
// copies each module's PrivacyInfo.xcprivacy into the module's resource bundle. This target depends
// on the umbrella, so SwiftPM builds every module's bundle beside its test bundle. Bazel's bundling
// is checked by //Tests/PrivacyManifests, so this runs under SwiftPM alone (SWIFT_PACKAGE), and on
// Apple platforms, the only ones that read a privacy manifest.

#if SWIFT_PACKAGE && canImport(Darwin)
import Foundation
import Testing

@Suite("Privacy manifests")
struct PrivacyManifestTests {
    private final class TestBundleMarker {}

    @Test("SwiftPM bundles every module's privacy manifest, unchanged, in Traffluent_<Module>.bundle")
    func everyManifestIsBundled() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources")
        let modules = try FileManager.default.contentsOfDirectory(atPath: sources.path(percentEncoded: false))
            .filter { FileManager.default.fileExists(atPath: sources.appending(path: "\($0)/PrivacyInfo.xcprivacy").path(percentEncoded: false)) }
            .sorted()
        let products = Bundle(for: TestBundleMarker.self).bundleURL.deletingLastPathComponent()
        let expectedModuleCount = 8

        #expect(modules.count == expectedModuleCount)
        for module in modules {
            let expected = try Data(contentsOf: sources.appending(path: "\(module)/PrivacyInfo.xcprivacy"))
            let bundle = try #require(Bundle(url: products.appending(path: "Traffluent_\(module).bundle")), "\(module)")
            let manifest = try #require(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"), "\(module)")
            let actual = try Data(contentsOf: manifest)
            #expect(actual == expected, "\(module)")
        }
    }
}
#endif
