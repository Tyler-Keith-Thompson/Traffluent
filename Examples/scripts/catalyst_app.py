#!/usr/bin/env python3
"""Builds the Apple example app (Examples/Apps/ExampleApp) for Mac Catalyst, into
Examples/.build/catalyst/ExampleApp.app.

    python3 Examples/scripts/catalyst_app.py            # `just example-catalyst`
    python3 Examples/scripts/catalyst_app.py --open     # then launch it

rules_apple has no Mac Catalyst rule, so Bazel can't bundle the app. SwiftPM builds the modules it
imports for the `macabi` triple from Examples/Package.swift (its Swift Build backend knows
Catalyst); swiftc then compiles the app's one source against them and links it; the bundle gets the
iOS app's Info.plist with the keys a Mac bundle needs, and an ad-hoc signature. Rejected: a second
Xcode project or a Tuist manifest for the one variant, each a build description kept in step by
hand beside scripts/modules.py.
"""

import argparse
import os
import plistlib
import subprocess
import sys

# The Examples/ package.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRATCH = os.path.join(ROOT, ".build", "catalyst")
APP = os.path.join(SCRATCH, "ExampleApp.app")
SOURCES = os.path.join(ROOT, "Apps", "ExampleApp")
TRIPLE = "arm64-apple-ios18.0-macabi"
# The modules the app imports, which between them reach every other it needs. The app links the
# object of every module SwiftPM builds for them, their dependencies' included.
TOP_MODULES = ["ExampleViews", "Destinations"]
SWIFT = ["env", "-u", "TOOLCHAINS", "xcrun", "--toolchain", "default"]


def run(cmd):
    print("+ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--open", action="store_true", help="launch the app once built")
    args = parser.parse_args()
    sdk = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], check=True, capture_output=True, text=True).stdout.strip()
    ios_support = os.path.join(sdk, "System", "iOSSupport")
    frameworks = os.path.join(ios_support, "System", "Library", "Frameworks")

    for module in TOP_MODULES:
        run(SWIFT + ["swift", "build", "--build-system", "swiftbuild", "--triple", TRIPLE, "--sdk", sdk,
                     "-Xswiftc", "-Fsystem", "-Xswiftc", frameworks, "--target", module, "--scratch-path", SCRATCH])
    products = os.path.join(SCRATCH, "out", "Products", "Debug-maccatalyst")

    executable = os.path.join(APP, "Contents", "MacOS", "ExampleApp")
    os.makedirs(os.path.dirname(executable), exist_ok=True)
    sources = sorted(os.path.join(SOURCES, f) for f in os.listdir(SOURCES) if f.endswith(".swift"))
    objects = sorted(os.path.join(products, f) for f in os.listdir(products) if f.endswith(".o"))
    run(SWIFT + ["swiftc", "-target", TRIPLE, "-sdk", sdk, "-Fsystem", frameworks,
                 "-L", os.path.join(ios_support, "usr", "lib"), "-I", products,
                 # swift-system's C module, which SystemPackage's interface (through Persistence's)
                 # imports; SwiftPM leaves its module map in the checkout, not among the products.
                 "-I", os.path.join(SCRATCH, "checkouts", "swift-system", "Sources", "CSystem", "include"),
                 "-module-name", "ExampleApp",
                 "-parse-as-library", "-swift-version", "6", *sources, *objects, "-o", executable])

    with open(os.path.join(SOURCES, "Info-iOS.plist"), "rb") as f:
        info = plistlib.load(f)
    info.update({
        "CFBundleExecutable": "ExampleApp",
        "CFBundleIdentifier": "com.example.traffluent.ios",
        "CFBundleName": "ExampleApp",
        "CFBundlePackageType": "APPL",
        # 2 is iPad, the idiom a Catalyst app scales from.
        "UIDeviceFamily": [2],
        "LSMinimumSystemVersion": "15.0",
    })
    with open(os.path.join(APP, "Contents", "Info.plist"), "wb") as f:
        plistlib.dump(info, f)
    run(["codesign", "--force", "--sign", "-", APP])
    print(f"Built {os.path.relpath(APP, os.path.dirname(ROOT))}")
    if args.open:
        run(["open", APP])
    return 0


if __name__ == "__main__":
    sys.exit(main())
