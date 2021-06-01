load(":private/providers.bzl", "NixBuildInfo", "NixLibraryInfo", "NixPkgsInfo")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")

def _nix_cc_impl(ctx):
    toolchain = ctx.toolchains["@io_tweag_rules_nixpkgs//:toolchain_type"]

    wrapper_file = ctx.actions.declare_file("wrapper.nix")
    toolchain.wrap(
        ctx,
        derivation = ctx.file.derivation,  # .nix file
        deps = ctx.attr.deps,
        nixpkgs = ctx.attr.nixpkgs,  # imports to grab from nixpkgs
        out = wrapper_file,
    )

    # need symlink for nix to not garbage collect results
    # we also symlink to this symlink if we have include or lib outputs
    out_symlink = ctx.actions.declare_directory("bazel-support")

    out_include_dir = None
    if ctx.attr.out_include_dir:
        out_include_dir = ctx.actions.declare_directory("include")

    out_lib_dir = None
    out_shared_libs = {}
    if ctx.attr.installs_libs:
        # TODO: create a debug mode that lists the contents of the lib directory
        # out_lib_dir = ctx.actions.declare_directory("lib")

        for out_shared_lib in ctx.attr.out_shared_libs:
            lib_name = "lib/" + out_shared_lib
            out_shared_libs[lib_name] = ctx.actions.declare_file(lib_name)

    toolchain.build(
        ctx,
        derivation = wrapper_file,  # .nix file
        # files to provide to nix for building
        srcs = ctx.files.srcs + [wrapper_file, ctx.file.derivation],
        deps = ctx.attr.deps,
        repo = ctx.attr.repo,
        out_symlink = out_symlink,
        out_include_dir = out_include_dir,
        out_include_dir_name = ctx.attr.out_include_dir,
        out_lib_dir = out_lib_dir,
        out_shared_libs = out_shared_libs,  # dict
    )

    maybe_nix_lib = [out_lib_dir] if out_lib_dir else []
    maybe_nix_include = [out_include_dir] if out_include_dir else []

    return [
        DefaultInfo(
            files = depset(direct = maybe_nix_include + maybe_nix_lib),
            runfiles = ctx.runfiles(files = []),
        ),
        NixLibraryInfo(
            info = NixBuildInfo(
                name = ctx.attr.name,
                nix_import = wrapper_file,
                extra_nix_files = [ctx.file.derivation],
                out_symlink = out_symlink,  # so we can require dependencies to be built
            ),
            deps = depset(
                direct = [dep[NixLibraryInfo].info for dep in ctx.attr.deps],
                transitive = [dep[NixLibraryInfo].deps for dep in ctx.attr.deps],
            ),
        ),
        _make_cc_info(ctx, out_include_dir, out_shared_libs),
    ]

def _make_cc_info(ctx, out_include_dir, out_shared_libs):
    cc_toolchain = find_cc_toolchain(ctx)

    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    compilation_context = None
    if out_include_dir:
        compilation_context = cc_common.create_compilation_context(
            headers = depset([out_include_dir]),
            system_includes = depset([out_include_dir.path]),
        )

    linking_context = None
    libraries_to_link = []
    for out_shared_lib in out_shared_libs.values():
        library_to_link = cc_common.create_library_to_link(
            actions = ctx.actions,
            feature_configuration = feature_configuration,
            dynamic_library = out_shared_lib,
            # this prevents most of the name mangling, but it may not be worth it
            # dynamic_library_symlink_path = out_shared_lib.basename,
            # static_library = ctx.file.static_library,
            cc_toolchain = cc_toolchain,
        )

        libraries_to_link.append(library_to_link)

    if libraries_to_link:
        linking_context = cc_common.create_linking_context(
            linker_inputs = depset([cc_common.create_linker_input(
                owner = ctx.label,
                libraries = depset(libraries_to_link),
            )]),
        )
    cc_info = CcInfo(
        compilation_context = compilation_context,
        linking_context = linking_context,
    )

nix_cc = rule(
    implementation = _nix_cc_impl,
    attrs = {
        "derivation": attr.label(allow_single_file = [".nix"], mandatory = True),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "input source files",
        ),
        "deps": attr.label_list(
            providers = [NixLibraryInfo],
        ),
        "nixpkgs": attr.string_list(
            doc = "package names to import from nixpkgs",
        ),
        "repo": attr.label(
            providers = [NixPkgsInfo],
            default = "@nixpkgs",
        ),
        "out_include_dir": attr.string(
            doc = "Name of the output subdirectory for header files",
            default = "include",
            mandatory = False,
        ),
        "installs_libs": attr.bool(default = False),
        "out_shared_libs": attr.string_list(
            doc = "List of shared libraries created by rule",
        ),
        # for find_cpp_toolchain
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    outputs = {
        "log": "%{name}.log",
        "path_info": "%{name}.path_info",
        "derivation": "%{name}.derivation",
    },
    fragments = ["cpp"],  # for configure_features
    toolchains = [
        "@io_tweag_rules_nixpkgs//:toolchain_type",
        "@bazel_tools//tools/cpp:toolchain_type",
    ],
    incompatible_use_toolchain_transition = True,
    executable = False,
    test = False,
)

def _nix_package_repository_impl(ctx):
    return [
        DefaultInfo(),
        NixPkgsInfo(
            nix_import = ctx.file.derivation,
        ),
    ]

nix_package_repository = rule(
    implementation = _nix_package_repository_impl,
    attrs = {
        "derivation": attr.label(allow_single_file = [".nix"], mandatory = True),
    },
    executable = False,
    test = False,
)
