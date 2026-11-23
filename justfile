PROJECT_ROOT := justfile_directory()
BAZEL := "bazel"

# Optimized builds use a separate output base: switching --compilation_mode changes the
# configuration, and sharing a base with debug builds would discard the analysis cache on every
# switch (which .bazelrc refuses). Each checkout gets its own, so two never wait on one server's
# lock or overwrite each other's outputs. It sits in Bazel's output user root under a 32-digit hex
# name like the debug base's, where tools/sweep-output-bases deletes it once its checkout is gone.
BAZEL_RELEASE_OUTPUT_BASE := cache_directory() / "bazel" / ("_bazel_" + env("USER", "root")) / replace_regex(sha256(PROJECT_ROOT + ":release"), '^(.{32}).*$', '$1')
BAZEL_RELEASE := "bazel --output_base=" + BAZEL_RELEASE_OUTPUT_BASE

# SwiftPM runs through Xcode's default toolchain. A development snapshot selected through
# TOOLCHAINS (or first on PATH via swiftly) can fail to read the SDK's Testing module.
SWIFT := "env -u TOOLCHAINS xcrun --toolchain default swift"

[doc('Build everything (default)')]
all: build

[doc('Build every target')]
build:
    {{BAZEL}} build //...

[doc('Run every test')]
test:
    {{BAZEL}} test //...

[doc('Run one test target, e.g. just test-one //Tests/GreetingsTests')]
test-one target:
    {{BAZEL}} test {{target}}

[doc('Run tests matching a filter, e.g. just filter Greeting')]
filter pattern:
    {{BAZEL}} test //... --test_filter={{pattern}}

[doc('Run the speed-reliant tests (the PerformanceTests targets) optimized (-O); the rest run in debug only')]
test-release:
    {{BAZEL_RELEASE}} test --config=release //...

[doc('Re-resolve SwiftPM dependencies for Bazel after editing PACKAGES in scripts/modules.py')]
resolve:
    cd {{PROJECT_ROOT}}/swift && {{SWIFT}} package resolve

[doc('Build via SwiftPM too, to verify the published package')]
spm:
    {{SWIFT}} build

[doc('Run the tests via SwiftPM')]
spm-test *args="":
    {{SWIFT}} test {{args}}

[doc('Build the library (not its tests) for watchOS arm64_32, a 32-bit Int, into .build/watchos')]
build-arm64_32:
    cd {{PROJECT_ROOT}} && xcodebuild build -scheme Traffluent-Package -destination generic/platform=watchOS -derivedDataPath .build/watchos -skipPackagePluginValidation -skipMacroValidation ARCHS=arm64_32 ONLY_ACTIVE_ARCH=NO -quiet

[doc('Verify both build systems agree — run before pushing')]
verify: test spm-test

[doc('Regenerate Package.swift and every BUILD.bazel from scripts/modules.py')]
modules:
    python3 {{PROJECT_ROOT}}/scripts/modules.py

[doc('Build the combined DocC site for every library module into .build/docs (what the DocC workflow publishes)')]
docs:
    {{BAZEL}} build //:docs
    rm -rf {{PROJECT_ROOT}}/.build/docs && mkdir -p {{PROJECT_ROOT}}/.build
    cp -RL {{PROJECT_ROOT}}/bazel-bin/docs {{PROJECT_ROOT}}/.build/docs && chmod -R u+w {{PROJECT_ROOT}}/.build/docs

[doc('Mutation testing: plant the bugs in scripts/mutants/<Module>.py and check the tests catch each, e.g. just mutate Greetings, or just mutate Greetings --all')]
mutate module *args="":
    python3 {{PROJECT_ROOT}}/scripts/mutate.py {{module}} {{args}}

[doc('Fuzz with libFuzzer, time-boxed (a swift.org toolchain through swiftly; Fuzz/README.md), e.g. just fuzz, or just fuzz FuzzGreetings -t 600')]
fuzz *args="":
    python3 {{PROJECT_ROOT}}/scripts/fuzz.py run {{args}}

[doc('Replay every fuzz corpus once, after a change')]
fuzz-regress *args="":
    python3 {{PROJECT_ROOT}}/scripts/fuzz.py regress {{args}}

[doc('Replay and minimize one crash, e.g. just fuzz-repro FuzzGreetings Fuzz/Crashes/FuzzGreetings/crash-…')]
fuzz-repro target input:
    python3 {{PROJECT_ROOT}}/scripts/fuzz.py repro {{target}} {{input}}

# ── Examples (Examples/, a SwiftPM package of its own; README.md, "Examples") ──

EXAMPLES := PROJECT_ROOT / "Examples"

[doc('Build every example app')]
examples: example-ios example-mac example-catalyst example-visionos example-watchos example-linux example-server

[doc('Run the examples’ tests (SwiftPM, in Examples/)')]
examples-test *args="":
    cd {{EXAMPLES}} && {{SWIFT}} test {{args}}

[doc('Write the store example’s tracking plan into Examples/TrackingPlan with the export-tracking-plan plugin, and fail if it differs from the committed (or staged) one')]
example-tracking-plan:
    cd {{EXAMPLES}} && {{SWIFT}} package --allow-writing-to-package-directory export-tracking-plan
    @git -C {{PROJECT_ROOT}} diff --exit-code -- Examples/TrackingPlan && \
        test -z "$(git -C {{PROJECT_ROOT}} ls-files --others --exclude-standard -- Examples/TrackingPlan)" || \
        { git -C {{PROJECT_ROOT}} status --short -- Examples/TrackingPlan; echo "Examples/TrackingPlan differs from the committed plan"; exit 1; }

[doc('Build the iPhone and iPad example, one universal app, for the simulator')]
example-ios:
    {{BAZEL}} build //Examples/Apps/ExampleApp:iOSExample

[doc('Build the Mac example')]
example-mac:
    {{BAZEL}} build //Examples/Apps/ExampleApp:MacExample

[doc('Build the iOS example for Mac Catalyst into Examples/.build/catalyst (rules_apple has no Catalyst rule), e.g. just example-catalyst --open')]
example-catalyst *args="":
    python3 {{EXAMPLES}}/scripts/catalyst_app.py {{args}}

[doc('Build the visionOS example for the simulator')]
example-visionos:
    {{BAZEL}} build //Examples/Apps/ExampleApp:VisionExample

[doc('Build the watchOS example for the simulator')]
example-watchos:
    {{BAZEL}} build //Examples/Apps/ExampleApp:WatchExample

# The Swift image CI's SwiftPM job runs in (.github/workflows/CI.yml).
LINUX_SWIFT_IMAGE := "swift:6.4"

[doc('Build the command-line and server examples on Linux, in Docker, and run the command-line one')]
example-linux:
    docker run --rm -v {{PROJECT_ROOT}}:/package -w /package/Examples {{LINUX_SWIFT_IMAGE}} bash -c \
        'swift build --product CommandLineExample --scratch-path .build/linux && swift build --product ServerExample --scratch-path .build/linux && .build/linux/debug/CommandLineExample'

[doc('Build the server example (Hummingbird); just serve-example runs it on 127.0.0.1:8080')]
example-server:
    cd {{EXAMPLES}} && {{SWIFT}} build --product ServerExample

[doc('Run the server example on 127.0.0.1:8080, printing each request it serves')]
serve-example:
    cd {{EXAMPLES}} && {{SWIFT}} run ServerExample

# The checkout of BenchmarkHarness whose benchmark-harness tool records simulated baselines.
BENCHMARK_HARNESS := env("BENCHMARK_HARNESS", home_directory() / "workspace" / "BenchmarkHarness")

[doc('Run the benchmarks, e.g. just bench, or just bench --target GreetingsBenchmarks')]
bench *args="":
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark {{args}}

[doc('Record the current results as the baseline named main')]
bench-baseline:
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark baseline update main

[doc('Compare the current results against the saved baseline')]
bench-compare:
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark baseline compare main

[doc("Record the benchmarks' simulated counts (Callgrind in a Linux VM; steady on a busy machine) as the simulated baseline, measuring only targets whose code changed (Bazel caches the rest), e.g. just bench-simulated, or just bench-simulated --target X")]
bench-simulated *args="": (_simulated-baseline "simulated" args)

[doc("Record simulated counts as simulated-current and compare them against the simulated baseline, e.g. just bench-simulated-compare --target X")]
bench-simulated-compare *args="": (_simulated-baseline "simulated-current" "--fresh " + args)
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark baseline compare simulated simulated-current {{args}}

[private]
_simulated-baseline name args:
    BENCHMARK_HARNESS={{BENCHMARK_HARNESS}} python3 {{PROJECT_ROOT}}/scripts/bench_simulated.py {{name}} {{args}}

[doc('Generate an Xcode project from the Bazel graph and open it')]
generate *args="":
    @bash scripts/generate-xcodeproj.sh {{args}}

[doc('Build optimized: the library and the speed-reliant tests, not the debug-only test targets')]
release:
    {{BAZEL_RELEASE}} build --config=release //...

[doc('Store the BuildBuddy API key in the login Keychain (asks for it), once per Mac: every project from the template then builds with the remote cache (tools/bazel)')]
buildbuddy-key:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r -s -p "BuildBuddy API key (hidden): " key
    echo
    if [ -z "$key" ]; then
        echo "No key entered; nothing stored" >&2
        exit 1
    fi
    # Through security's own command reader, so the key never appears in a process's arguments.
    printf 'add-generic-password -U -s buildbuddy -a api-key -l "BuildBuddy API key" -w %s\n' "$key" | security -i >/dev/null
    echo "Stored. Builds use BuildBuddy from the next Bazel command."

[doc('Set this repository’s BUILDBUDDY_API_KEY Actions secret from the Keychain with gh, so CI uses the remote cache too')]
ci-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! key="$(security find-generic-password -s buildbuddy -a api-key -w 2>/dev/null)"; then
        echo "No BuildBuddy API key in the Keychain; store it with just buildbuddy-key" >&2
        exit 1
    fi
    printf '%s' "$key" | gh secret set BUILDBUDDY_API_KEY

# The checkout of ProjectTemplate this project came from; .template.json records the commit.
PROJECT_TEMPLATE := env("PROJECT_TEMPLATE", home_directory() / "workspace" / "ProjectTemplate")

[doc('Merge the project template’s changes since .template.json’s commit into this checkout (needs a clean worktree), e.g. just template-update, or just template-update --to <commit>')]
template-update *args="":
    python3 {{PROJECT_TEMPLATE}}/template.py update {{PROJECT_ROOT}} {{args}}

[doc('Remove all build artifacts')]
clean:
    {{BAZEL}} clean
    {{BAZEL_RELEASE}} clean || true
    rm -rf {{PROJECT_ROOT}}/.build
    rm -rf {{PROJECT_ROOT}}/Benchmarks/.build
    rm -rf {{PROJECT_ROOT}}/Fuzz/.build
    rm -rf {{PROJECT_ROOT}}/Examples/.build

[doc('Print the dependency graph of a target')]
deps target="//Sources/Traffluent":
    {{BAZEL}} query 'deps({{target}})' --output=label_kind

[doc('List every buildable target')]
targets:
    {{BAZEL}} query '//...' --output=label_kind
