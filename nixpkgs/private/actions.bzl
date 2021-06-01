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
    wrapper_file = ctx.actions.declare_file("wrapper.nix")
    ctx.actions.write(
        output = wrapper_file,
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

def nix_build(
        ctx,
        derivation,
        srcs,
        deps,
        repo,  # nix repo
        out_symlink,
        out_include_dir,
        out_include_dir_name,
        out_lib_dir,
        out_shared_libs):
    """ runs nix-build on a set of sources """
    toolchain = ctx.toolchains["@io_tweag_rules_nixpkgs//:toolchain_type"]

    _nix_debug_build(ctx, out_symlink)  # add optional debug outputs

    if out_include_dir:
        ctx.actions.run_shell(
            inputs = [out_symlink],
            outputs = [out_include_dir],
            command = "cp -R {}/result/{}/* {}".format(
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
                "cp -R {}/result/{} {}".format(
                    out_symlink.path,
                    lib_name,
                    out_shared_libs[lib_name].path,
                )
                for lib_name in out_shared_libs
            ]),
        )

    if out_lib_dir:
        ctx.actions.run_shell(
            inputs = [out_symlink],
            outputs = [out_lib_dir] + out_shared_libs,
            command = "cp -R {}/result/{}/* {}".format(
                out_symlink.path,
                "lib",
                out_lib_dir.path,
            ),
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
        ] + nixpath_entries + [
            derivation.path,
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
