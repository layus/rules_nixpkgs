load(":private/providers.bzl", "NixLibraryInfo", "NixPkgsInfo")

NIX_WRAPPER_TEMPLATE = """
let
  nixpkgs = import <nixpkgs> {{}};
  deps = {{
    {nixpkg_deps}
    {internal_deps}
  }};
in import <{nix_file_path}> deps
"""

def nix_wrapper(ctx, derivation, deps, nixpkgs, out):
    """
    generates a script that provides exactly the dependencies of this build.
    """
    ctx.actions.write(
        output = out,
        content = NIX_WRAPPER_TEMPLATE.format(
            nixpkg_deps = "\n    ".join([
                "{name} = nixpkgs.{name};".format(name = name)
                for name in nixpkgs
            ]),
            internal_deps = "\n    ".join([
                "{name} = import <{nix_file_path}>;".format(
                    name = dep[NixLibraryInfo].info.name,
                    nix_file_path = dep[NixLibraryInfo].info.nix_import.path,
                )
                for dep in deps
            ]),
            nix_file_path = derivation.path,
        ),
    )

def _nix_debug_build(ctx, out_symlink):
    toolchain = ctx.toolchains["@io_tweag_rules_nixpkgs//:toolchain_type"]

    # <name>.path_info generates a file with the referenced nix store paths
    ctx.actions.run_shell(
        inputs = [out_symlink],
        outputs = [ctx.outputs.path_info],
        command = "{} path-info -r {}/result > {}".format(
            toolchain.nixinfo.nix_bin_path,
            out_symlink.path,
            ctx.outputs.path_info.path,
        ),
    )

    # <name>.log generates a file with the nix build log for this target
    ctx.actions.run_shell(
        inputs = [out_symlink],
        outputs = [ctx.outputs.log],
        command = "{} log {}/result > {}".format(
            toolchain.nixinfo.nix_bin_path,
            out_symlink.path,
            ctx.outputs.log.path,
        ),
    )

    # <name>.derivation shows the derivation for this target
    ctx.actions.run_shell(
        inputs = [out_symlink],
        outputs = [ctx.outputs.derivation],
        command = "{} show-derivation {}/result > {}".format(
            toolchain.nixinfo.nix_bin_path,
            out_symlink.path,
            ctx.outputs.derivation.path,
        ),
    )

    ctx.actions.run_shell(
        inputs = [out_symlink],
        outputs = [ctx.outputs.lib_list],
        command = "find {}/result/lib > {}".format(
            out_symlink.path,
            ctx.outputs.lib_list.path,
        ),
    )

def _nix_docker_helper(ctx, out_symlink):
    toolchain = ctx.toolchains["@io_tweag_rules_nixpkgs//:toolchain_type"]

    # Create a tarball with runtime dependencies of built package.
    ctx.actions.run_shell(
        inputs = [out_symlink],
        outputs = [ctx.outputs.tar],
        command = " ".join([
            toolchain.nixinfo.nix_store_bin_path,
            "-q -R --include-outputs",
            "{}/result".format(out_symlink.path),
            "|",
            "xargs tar c",
            ">",
            ctx.outputs.tar.path,
        ]),
    )

def nix_build(
        ctx,
        derivation,
        srcs,
        deps,
        repo,  # nix repo
        out_symlink,
        out_include_dir,
        out_include_dir_name,
        out_lib_dir_name,
        out_shared_libs,
        out_static_libs):
    """ runs nix-build on a set of sources """
    toolchain = ctx.toolchains["@io_tweag_rules_nixpkgs//:toolchain_type"]

    _nix_debug_build(ctx, out_symlink)  # add optional debug outputs
    _nix_docker_helper(ctx, out_symlink)

    if out_include_dir:
        ctx.actions.run_shell(
            inputs = [out_symlink],
            outputs = [out_include_dir],
            command = "cp -R {}/{}/* {}".format(
                out_symlink.path,
                out_include_dir_name,
                out_include_dir.path,
            ),
        )

    if out_shared_libs:
        ctx.actions.run_shell(
            inputs = [out_symlink],
            outputs = out_shared_libs.values(),
            command = "\n".join([
                "cp -R {}/{}/{} {}".format(
                    out_symlink.path,
                    out_lib_dir_name,
                    lib_name,
                    out_shared_libs[lib_name].path,
                )
                for lib_name in out_shared_libs
            ]),
        )

    if out_static_libs:
        ctx.actions.run_shell(
            inputs = [out_symlink],
            outputs = out_static_libs.values(),
            command = "\n".join([
                "cp -R {}/{}/{} {}".format(
                    out_symlink.path,
                    out_lib_dir_name,
                    lib_name,
                    out_static_libs[lib_name].path,
                )
                for lib_name in out_static_libs
            ]),
        )

    input_nix_out_symlinks = []
    nix_file_deps = []
    nixpath_entries = []
    for dep in deps:
        info = dep[NixLibraryInfo].info

        nixpath_entries += ["-I", "{}={}".format(info.name, info.nix_import.path)]
        nix_file_deps.append(info.nix_import)
        nix_file_deps += info.extra_nix_files
        input_nix_out_symlinks.append(info.out_symlink)

    maybe_build_attr = []
    if ctx.attr.build_attribute:
        maybe_build_attr = [
            "-A",
            ctx.attr.build_attribute,
        ]

    ctx.actions.run(
        outputs = [out_symlink],
        inputs = srcs + input_nix_out_symlinks + nix_file_deps + [repo[NixPkgsInfo].nix_import],
        executable = toolchain.nixinfo.nix_build_bin_path,
        env = {
            # nix tries to update a database entry for it's cache state
            # in the home directory, and we don't want that.
            "XDG_CACHE_HOME": ".",
        },
        arguments = [
            "-I",
            ".",
            "-I",
            "nixpkgs={}".format(repo[NixPkgsInfo].nix_import.path),
        ] + nixpath_entries + maybe_build_attr + [
            derivation.path,
            "--keep-failed",  # TODO(danny): when should we enable this?
            "--show-trace",
            "--out-link",
            "{}/result".format(out_symlink.path),
        ],
        mnemonic = "NixBuild",
        # .bazelrc needs:
        # build --sandbox_writable_path=/nix
        # build --sandbox_writable_path=/dev/pts
        #
        # or this is required:
        # execution_requirements = {
        #     "no-sandbox": "1",
        # },
    )

GENERATE_NIX_MANIFEST = """
set -euo pipefail
store_paths=()

# loop through store paths in arguments
for store_path in "$@"
do
    # query nix store to grab runtime dependencies of each store path
    paths=( $({nix_store_bin_path} -q -R --include-outputs $store_path) )
    # concatenate new store paths
    store_paths=( "${{store_paths[@]+"${{store_paths[@]}}"}}" "${{paths[@]}}" )
done

# sort (and deduplicate) store paths
IFS=$'\n' sorted_store_paths=($(sort -u <<<"${{store_paths[*]}}"))
unset IFS

# print merged list to manifest file
printf "%s\n" "${{sorted_store_paths[@]}}" >> {manifest_path}
"""

def nix_layer(ctx, deps, store_paths, output_manifest):
    toolchain = ctx.toolchains["@io_tweag_rules_nixpkgs//:toolchain_type"]

    # Create a sorted (and deduplicated) list of nix store paths needed by deps.
    ctx.actions.run_shell(
        inputs = deps,
        outputs = [output_manifest],
        command = GENERATE_NIX_MANIFEST.format(
            nix_store_bin_path = toolchain.nixinfo.nix_store_bin_path,
            manifest_path = output_manifest.path,
        ),
        arguments = store_paths,
    )

    ctx.actions.run_shell(
        inputs = [output_manifest],
        outputs = [ctx.outputs.tar],
        # TODO(danny): this is probably not hermetic, but it seems to work okay right now
        # It would be better to replace this with an invocation of rules_docker's tar building
        # code in python. If we rely at all on python, I'd love to replace the sketchy bash
        # script above too.
        command = "cat {manifest_path} | xargs tar c > {tar_output_path}".format(
            manifest_path = output_manifest.path,
            tar_output_path = ctx.outputs.tar.path,
        ),
    )
