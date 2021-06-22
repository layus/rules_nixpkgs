load(
    ":private/providers.bzl",
    "NixBuildInfo",
    "NixDepsInfo",
    "NixDerivationInfo",
    "NixLibraryInfo",
    "NixPkgsInfo",
)
load(":private/aspects.bzl", "nix_deps_aspect")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain")

def _declare_lib(ctx, lib_name):
    return ctx.actions.declare_file("{}-lib/{}".format(ctx.label.name, lib_name))

def _nix_cc_impl(ctx):
    toolchain = ctx.toolchains["@io_tweag_rules_nixpkgs//:toolchain_type"]

    wrapper_file = ctx.actions.declare_file("{}-wrapper.nix".format(ctx.label.name))
    toolchain.wrap(
        ctx,
        derivation = ctx.file.derivation,  # .nix file
        deps = ctx.attr.deps,
        nixpkgs = ctx.attr.nixpkgs,  # imports to grab from nixpkgs
        out = wrapper_file,
    )

    # need symlink for nix to not garbage collect results
    # we also symlink to this symlink if we have include or lib outputs
    out_symlink = ctx.actions.declare_directory("{}-bazel-support".format(ctx.label.name))

    out_include_dir = None
    if ctx.attr.out_include_dir:
        out_include_dir = ctx.actions.declare_directory("{}-include".format(ctx.label.name))

    out_shared_libs = {}
    out_static_libs = {}
    for lib_name in ctx.attr.out_shared_libs:
        out_shared_libs[lib_name] = _declare_lib(ctx, lib_name)
    for lib_name in ctx.attr.out_static_libs:
        out_static_libs[lib_name] = _declare_lib(ctx, lib_name)

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
        out_lib_dir_name = ctx.attr.out_lib_dir,
        out_shared_libs = out_shared_libs,  # dict
        out_static_libs = out_static_libs,  # dict
    )

    maybe_nix_include = [out_include_dir] if out_include_dir else []

    return [
        DefaultInfo(
            files = depset(direct = maybe_nix_include),
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
        NixDerivationInfo(
            out_symlink = out_symlink,
            store_path = out_symlink.path + "/result",  # TODO: don't hardcode expected result path!
        ),
        _make_cc_info(ctx, out_include_dir, out_shared_libs, out_static_libs),
    ]

def _make_cc_info(ctx, out_include_dir, out_shared_libs, out_static_libs):
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
            cc_toolchain = cc_toolchain,
        )

        libraries_to_link.append(library_to_link)

    for out_static_lib in out_static_libs.values():
        library_to_link = cc_common.create_library_to_link(
            actions = ctx.actions,
            feature_configuration = feature_configuration,
            static_library = out_static_lib,
            cc_toolchain = cc_toolchain,
        )

        libraries_to_link.append(library_to_link)

    user_link_flags = ctx.attr.linkopts

    if libraries_to_link:
        linking_context = cc_common.create_linking_context(
            linker_inputs = depset([cc_common.create_linker_input(
                owner = ctx.label,
                libraries = depset(libraries_to_link),
                user_link_flags = depset(user_link_flags),
            )]),
        )
    return CcInfo(
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
        "build_attribute": attr.string(
            doc = "Nix attribute to build (passes -A <build_attribute> to command line)",
        ),
        "linkopts": attr.string_list(
        ),
        "out_include_dir": attr.string(
            doc = "Name of the output subdirectory for header files (usually under result/include)",
            default = "result/include",
            mandatory = False,
        ),
        "out_shared_libs": attr.string_list(
            doc = "List of shared libraries created by rule",
        ),
        "out_static_libs": attr.string_list(
            doc = "List of static libraries created by rule",
        ),
        "out_lib_dir": attr.string(
            doc = "Name of the output subdirectory for library files",
            default = "result/lib",
            mandatory = False,
        ),
        # for find_cpp_toolchain
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    outputs = {
        "log": "%{name}.log",
        "path_info": "%{name}.path_info",
        "derivation": "%{name}.derivation",
        "lib_list": "%{name}.lib_list",
        "tar": "%{name}.tar",
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

def _nix_bundleable_impl(ctx):
    return [NixDerivationInfo(
        out_symlink = None,  # only used for nix_cc
        store_path = ctx.attr.store_path,
    )]

nix_bundleable = rule(
    implementation = _nix_bundleable_impl,
    attrs = {
        "store_path": attr.string(doc = "nix store path of derivation", mandatory = True),
    },
    executable = False,
    test = False,
)

def _nix_deps_layer_impl(ctx):
    toolchain = ctx.toolchains["@io_tweag_rules_nixpkgs//:toolchain_type"]

    output = ctx.actions.declare_file("{}.nix-manifest".format(ctx.label.name))

    store_paths = []
    out_symlinks = []
    for dep in ctx.attr.deps:
        store_paths += dep[NixDepsInfo].store_paths.to_list()
        out_symlinks.append(dep[NixDepsInfo].out_symlinks)

    toolchain.layer(ctx, depset([], transitive = out_symlinks), store_paths, output)

    return [
        DefaultInfo(
            files = depset(direct = [output]),
            runfiles = ctx.runfiles(files = []),
        ),
    ]

nix_deps_layer = rule(
    implementation = _nix_deps_layer_impl,
    attrs = {
        "deps": attr.label_list(aspects = [nix_deps_aspect]),
    },
    toolchains = [
        "@io_tweag_rules_nixpkgs//:toolchain_type",
    ],
    outputs = {
        "tar": "%{name}.tar",
    },
)
