load("//nixpkgs:private/actions.bzl", "nix_build", "nix_layer", "nix_wrapper")

NixInfo = provider(
    doc = "NixInfo provides information about the nix toolchain",
    fields = {
        "nix_build_bin_path": "Path to nix-build executable",
        "nix_store_bin_path": "Path to nix-store executable",
        "nix_bin_path": "Path to nix executable",
    },
)

def _nix_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        # Public interface of toolchain
        build = nix_build,
        wrap = nix_wrapper,

        # Docker helper actions
        layer = nix_layer,

        # Providers for toolchain actions
        nixinfo = NixInfo(
            nix_build_bin_path = ctx.attr.nix_build_bin_path,
            nix_store_bin_path = ctx.attr.nix_store_bin_path,
            nix_bin_path = ctx.attr.nix_bin_path,
        ),
    )
    return [toolchain_info]

nix_toolchain = rule(
    implementation = _nix_toolchain_impl,
    attrs = {
        "nix_build_bin_path": attr.string(),
        "nix_store_bin_path": attr.string(),
        "nix_bin_path": attr.string(),
    },
)

def _auto_nix_toolchain(repository_ctx):
    repository_ctx.file(
        "BUILD.bazel",
        content = """
load("@io_tweag_rules_nixpkgs//nixpkgs:toolchains/nix.bzl", "nix_toolchain")
load("@io_tweag_rules_nixpkgs//:defs.bzl", "nix_package_repository")

nix_toolchain(
    name = "nix_toolchain",
    nix_build_bin_path = "{nix_build_bin_path}",
    nix_store_bin_path = "{nix_store_bin_path}",
    nix_bin_path = "{nix_bin_path}",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "toolchain",
    toolchain = ":nix_toolchain",
    toolchain_type = "@io_tweag_rules_nixpkgs//:toolchain_type",
)
""".format(
            nix_build_bin_path = repository_ctx.which("nix-build"),
            nix_store_bin_path = repository_ctx.which("nix-store"),
            nix_bin_path = repository_ctx.which("nix"),
        ),
    )

    repository_ctx.file(
        "WORKSPACE",
        content = """
register_toolchains("//:nix_toolchain")
""",
    )

auto_nix_toolchain = repository_rule(
    implementation = _auto_nix_toolchain,
    local = True,
    attrs = {},
)
