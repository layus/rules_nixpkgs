load(":providers.bzl", "NixDepsInfo", "NixDerivationInfo")

def _nix_deps_aspect_impl(target, ctx):
    store_paths = []
    out_symlinks = []

    # Collect direct store paths and bazel-support symlinks in data + deps attrs.
    if NixDerivationInfo in target:
        store_paths.append(target[NixDerivationInfo].store_path)

        # The bazel-support symlink is only passed by nix_cc rules.
        out_symlink = target[NixDerivationInfo].out_symlink
        if out_symlink != None:
            out_symlinks.append(out_symlink)

    # Forward all store paths and bazel-support symlinks in deps
    direct_deps = []

    indirect_store_paths = []
    indirect_out_symlinks = []
    if hasattr(ctx.rule.attr, "data"):
        direct_deps += [dep for dep in ctx.rule.attr.data]
    if hasattr(ctx.rule.attr, "deps"):
        direct_deps += [dep for dep in ctx.rule.attr.deps]
    for dep in direct_deps:
        if NixDepsInfo not in dep:
            continue
        indirect_store_paths.append(dep[NixDepsInfo].store_paths)
        indirect_out_symlinks.append(dep[NixDepsInfo].out_symlinks)

    return [NixDepsInfo(store_paths = depset(
        direct = store_paths,
        transitive = indirect_store_paths,
    ), out_symlinks = depset(
        direct = out_symlinks,
        transitive = indirect_out_symlinks,
    ))]

nix_deps_aspect = aspect(
    implementation = _nix_deps_aspect_impl,
    attr_aspects = ["data", "deps"],
)
