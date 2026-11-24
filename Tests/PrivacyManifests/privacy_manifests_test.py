"""Every privacy manifest reaches a Bazel-built bundle (RESOURCES in scripts/modules.py).

The arguments name the manifest bundles, `Traffluent_<Module>`; the data holds the Mac bundle that
links those modules and each module's manifest at its workspace path. rules_apple writes the bundle
as a .zip unless tree artifacts are on, so both are read.
"""

import os
import plistlib
import sys
import unittest
import zipfile

BUNDLE = "Tests/PrivacyManifests/PrivacyManifestsBundle"
MANIFEST = "PrivacyInfo.xcprivacy"


def bundled_files():
    """Every file in the built bundle, as {path inside the bundle: bytes}."""
    if os.path.isdir(BUNDLE + ".bundle"):
        root = BUNDLE + ".bundle"
        files = {}
        for directory, _, names in os.walk(root):
            for name in names:
                path = os.path.join(directory, name)
                with open(path, "rb") as file:
                    files[os.path.relpath(path, root)] = file.read()
        return files
    with zipfile.ZipFile(BUNDLE + ".zip") as archive:
        prefix = "PrivacyManifestsBundle.bundle/"
        return {name.removeprefix(prefix): archive.read(name) for name in archive.namelist() if not name.endswith("/")}


class PrivacyManifestsTest(unittest.TestCase):
    bundles = []

    def test_each_module_manifest_is_bundled_as_its_source(self):
        files = bundled_files()
        for bundle in self.bundles:
            module = bundle.split("_", 1)[1]
            with self.subTest(bundle=bundle):
                expected = f"Contents/Resources/{bundle}.bundle/{MANIFEST}"
                self.assertIn(expected, files, f"{bundle}.bundle holds no {MANIFEST}; bundled: {sorted(files)}")
                with open(f"Sources/{module}/{MANIFEST}", "rb") as file:
                    source = plistlib.loads(file.read())
                actual = plistlib.loads(files[expected])
                self.assertEqual(source, actual)

    def test_no_manifest_declares_tracking(self):
        for bundle in self.bundles:
            module = bundle.split("_", 1)[1]
            with self.subTest(bundle=bundle):
                with open(f"Sources/{module}/{MANIFEST}", "rb") as file:
                    actual = plistlib.loads(file.read())
                self.assertIs(actual["NSPrivacyTracking"], False)
                self.assertEqual(actual["NSPrivacyTrackingDomains"], [])
                for collected in actual["NSPrivacyCollectedDataTypes"]:
                    self.assertIs(collected["NSPrivacyCollectedDataTypeTracking"], False)


if __name__ == "__main__":
    PrivacyManifestsTest.bundles = sys.argv[1:]
    unittest.main(argv=sys.argv[:1])
