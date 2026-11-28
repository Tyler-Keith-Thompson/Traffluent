"""A test that a Swift program builds and runs, or fails to build with the errors it must report.

`swift_link_test` compiles `main` against the modules of `deps`, with `plugins` loaded, then links
the object with every static archive the deps carry, and runs the program. It passes, with no
`expected_errors`, when every step succeeds and the program exits 0; with `expected_errors`, when
the compile or the link fails and the output holds every one of them. It is what shows a mistake
that only the linker can see, such as two modules declaring the same unique key, in the place the
developer meets it.

Each archive in `deps` is linked whole (`-force_load` on Apple platforms, `--whole-archive`
elsewhere), as SwiftPM and Bazel link a target's modules, except those of `on_demand`, which the
linker reads only for the members something references: how an archive behaves in a build that
doesn't force it in.

    swift_link_test(
        name = "DuplicateEventNames",
        size = "small",
        main = "DuplicateEventNames.swift",
        expected_errors = ["$linkerset_kind_65766E74_key_OrderPlaced"],
        on_demand = [":Checkout"],
        tags = ["debug-only"],
        deps = [":Checkout", ":Orders"],
    )

Each source in `loaded_libraries` is compiled on its own into a shared library of the module named
beside it, against the same modules and plugins as `main`, and its path is passed to the program as
an argument, in the order listed, for the program to open with `dlopen`: how a plug-in reaches a
running program. A library resolves the symbols of the deps' modules against the program, which
holds them (`-undefined dynamic_lookup` on Apple platforms; the program exports its symbols with
`--export-dynamic` elsewhere), so each module has one copy in the process and the library holds
only its own source.

The compiler is the host's, as in `swift_compile_failure_test`: `xcrun swiftc` on macOS, `swiftc`
on the PATH elsewhere, linking with lld there as Bazel does. The link adds only the deps' own link
flags, so it neither dead-strips nor treats warnings as errors.

Ported from LinkerSets' tools/link_test.bzl (0.0.31), with `loaded_libraries` and `copts` added and
the deps' C modules found as `swift_compile_failure_test` finds them.
"""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_swift//swift:providers.bzl", "SwiftInfo")

_SCRIPT = """#!/bin/sh
set -u
if command -v xcrun >/dev/null 2>&1; then
    swiftc="xcrun swiftc"
    whole_start="-Xlinker -force_load -Xlinker"
    whole_end=""
    group_start=""
    group_end=""
    library_extension="dylib"
    library_flags="-Xlinker -undefined -Xlinker dynamic_lookup"
    export_flags=""
else
    # lld, as Bazel's own links use: the flags rules_swift hands on (-z nostart-stop-gc) are lld's.
    swiftc="swiftc -use-ld=lld"
    whole_start="-Xlinker --whole-archive"
    whole_end="-Xlinker --no-whole-archive"
    # GNU linkers read an archive once, in order; a group lets the archives refer to each other.
    group_start="-Xlinker --start-group"
    group_end="-Xlinker --end-group"
    library_extension="so"
    library_flags=""
    export_flags="-Xlinker --export-dynamic"
fi
work="${TEST_TMPDIR:-/tmp}/link"
mkdir -p "$work"
cache="$work/module-cache"
archives=""
for archive in %s; do
    archives="$archives $whole_start $archive $whole_end"
done
for archive in %s; do
    archives="$archives $archive"
done
# -disable-sandbox: on macOS the compiler runs a plugin in a sandbox of its own, which can't start
# inside Bazel's. The deps' module paths and the plugins serve the program and each library alike.
compile() {
    $swiftc -swift-version 6 -disable-sandbox -module-cache-path "$cache" %s "$@"
}
output="$(compile -c -module-name Main "%s" -o "$work/main.o" 2>&1)"
status=$?
libraries=""
while IFS=' ' read -r module source; do
    [ -n "$module" ] || continue
    [ "$status" -eq 0 ] || break
    library="$work/lib$module.$library_extension"
    output="$output
$(compile -emit-library -module-name "$module" "$source" $library_flags -o "$library" 2>&1)"
    status=$?
    libraries="$libraries $library"
done <<'LIBRARIES'
%s
LIBRARIES
if [ "$status" -eq 0 ]; then
    output="$output
$($swiftc "$work/main.o" $group_start $archives $group_end %s $export_flags -o "$work/program" 2>&1)"
    status=$?
fi
if [ "$status" -eq 0 ]; then
    output="$output
$("$work/program" $libraries 2>&1)"
    status=$?
fi
if [ -z "$(printf '%%s' '%s' | tr -d '[:space:]')" ]; then
    [ "$status" -eq 0 ] && exit 0
    echo "%s must build and run, but:"
    echo "$output"
    exit 1
fi
if [ "$status" -eq 0 ]; then
    echo "%s built and ran, but it must fail to build."
    echo "$output"
    exit 1
fi
missing=0
while IFS= read -r expected; do
    [ -n "$expected" ] || continue
    case "$output" in
        *"$expected"*) ;;
        *) echo "The output lacks: $expected"; missing=1 ;;
    esac
done <<'EXPECTED'
%s
EXPECTED
if [ "$missing" -ne 0 ]; then
    echo
    echo "$output"
    exit 1
fi
"""

def _quote(text):
    return "'" + text.replace("'", "'\\''") + "'"

def _static_archives(target):
    """The static archives `target` links: its own and its dependencies'."""
    archives = []
    for linker_input in target[CcInfo].linking_context.linker_inputs.to_list():
        for library in linker_input.libraries:
            archive = library.static_library or library.pic_static_library
            if archive:
                archives.append(archive)
    return archives

def _swift_link_test_impl(ctx):
    modules = depset(transitive = [dep[SwiftInfo].transitive_modules for dep in ctx.attr.deps]).to_list()
    files = []
    transitive_files = []
    clang_arguments = []
    directories = {}
    for module in modules:
        if module.swift and module.swift.swiftmodule:
            files.append(module.swift.swiftmodule)
            directories[module.swift.swiftmodule.short_path.rpartition("/")[0]] = None

        # A C module a Swift module imports (swift-system's CSystem), found as
        # swift_compile_failure_test finds it.
        if module.clang:
            module_map = module.clang.module_map
            if module_map and hasattr(module_map, "short_path"):
                files.append(module_map)
                clang_arguments += ["-Xcc", "-fmodule-map-file=" + module_map.short_path]
            context = module.clang.compilation_context
            if context:
                transitive_files.append(context.headers)
                for include in context.includes.to_list() + context.quote_includes.to_list() + context.system_includes.to_list():
                    # Paths from the execution root, where an external repository's files sit
                    # under external/; the test runs from the main repository's runfiles, beside
                    # the others'.
                    clang_arguments += ["-Xcc", "-I" + ("../" + include.removeprefix("external/") if include.startswith("external/") else include)]
    arguments = ["-I " + _quote(directory) for directory in directories] + [_quote(argument) for argument in clang_arguments + ctx.attr.copts]
    for target, module_name in ctx.attr.plugins.items():
        plugin = target[DefaultInfo].files_to_run.executable
        files.append(plugin)
        arguments.append("-load-plugin-executable " + _quote(plugin.short_path + "#" + module_name))

    # rules_swift names a library's own archive lib<name>.a; its dependencies' stay whole.
    on_demand = {}
    for dep in ctx.attr.on_demand:
        for archive in _static_archives(dep):
            if archive.basename == "lib" + dep.label.name + ".a":
                on_demand[archive.short_path] = None
    archives = {}
    # Flags for the clang driver that links, such as -ObjC, which swiftc hands on with -Xclang-linker.
    # Those naming Bazel's Xcode placeholder are left out: only Bazel's own wrapper fills it in, and
    # the host's swiftc finds the same paths itself. A flag that names one of a linker input's files
    # (on Linux, each module's .modulewrap.o and its @.autolink list of libraries) names it by its
    # path from the execution root, so it is rewritten to the file's place in the runfiles.
    linkopts = []
    for dep in ctx.attr.deps:
        for archive in _static_archives(dep):
            archives[archive.short_path] = archive
        for linker_input in dep[CcInfo].linking_context.linker_inputs.to_list():
            inputs = {file.path: file for file in linker_input.additional_inputs}
            files += inputs.values()
            for option in linker_input.user_link_flags:
                if "__BAZEL_XCODE_" in option:
                    continue
                prefix = "@" if option.startswith("@") else ""
                named = inputs.get(option.removeprefix("@"))
                linkopts.append(prefix + named.short_path if named else option)
    whole = [path for path in archives if path not in on_demand]
    files += archives.values()

    # One line per library, its module's name and then its source.
    libraries = "\n".join([module + " " + target.files.to_list()[0].short_path for target, module in ctx.attr.loaded_libraries.items()])
    files += [file for target in ctx.attr.loaded_libraries for file in target.files.to_list()]

    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        script,
        _SCRIPT % (
            " ".join([_quote(path) for path in whole]),
            " ".join([_quote(path) for path in on_demand]),
            " ".join(arguments),
            ctx.file.main.short_path,
            libraries,
            " ".join(["-Xclang-linker " + _quote(option) for option in linkopts]),
            "".join(ctx.attr.expected_errors).replace("'", ""),
            ctx.file.main.short_path,
            ctx.file.main.short_path,
            "\n".join(ctx.attr.expected_errors),
        ),
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = files + [ctx.file.main], transitive_files = depset(transitive = transitive_files))
    for target in ctx.attr.plugins:
        runfiles = runfiles.merge(target[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = script, runfiles = runfiles)]

swift_link_test = rule(
    implementation = _swift_link_test_impl,
    doc = "Passes when `main`, linked with the archives of `deps`, builds and runs, or fails to build with every one of `expected_errors`.",
    attrs = {
        "main": attr.label(allow_single_file = [".swift"], mandatory = True),
        "deps": attr.label_list(providers = [SwiftInfo, CcInfo]),
        "on_demand": attr.label_list(
            providers = [CcInfo],
            doc = "Deps whose own archive the linker reads only for the members something references, rather than whole.",
        ),
        "plugins": attr.label_keyed_string_dict(
            cfg = "exec",
            doc = "Compiler plugins to load, each with its module name, which `-load-plugin-executable` pairs with it.",
        ),
        "expected_errors": attr.string_list(doc = "Text the build's output must hold; none for a program that must build and run."),
        "copts": attr.string_list(doc = "Flags for the compiler, for `main` and each of `loaded_libraries`, such as `-O`."),
        "loaded_libraries": attr.label_keyed_string_dict(
            allow_files = [".swift"],
            doc = "Sources each compiled into a shared library of the module named beside it, whose paths the program gets as arguments, to open with `dlopen`.",
        ),
    },
    test = True,
)
