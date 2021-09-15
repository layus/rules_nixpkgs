def _nix_pip_impl(repository_ctx):
    repository_ctx.file(
        "default.nix",
        repository_ctx.read(repository_ctx.path(repository_ctx.attr.nix_file)),
        executable = False,
        legacy_utf8 = False,
    )

    repository_ctx.file(
        "pyproject.toml",
        repository_ctx.read(repository_ctx.path(repository_ctx.attr.pyproject_file)),
        executable = False,
        legacy_utf8 = False,
    )

    repository_ctx.file(
        "poetry.lock",
        repository_ctx.read(repository_ctx.path(repository_ctx.attr.lock_file)),
        executable = False,
        legacy_utf8 = False,
    )

    nix_build_path = repository_ctx.which("nix-build")

    timeout = 8640000
    repository_ctx.report_progress("Building Nix derivation")
    exec_result = repository_ctx.execute([nix_build_path])
    if exec_result.return_code:
        fail(exec_result.stderr)
    output_path = exec_result.stdout.splitlines()[-1]

    repository_ctx.file("BUILD.bazel", repository_ctx.read(output_path))

nix_pip = repository_rule(
    implementation = _nix_pip_impl,
    attrs = {
        "nix_file": attr.label(
            allow_single_file = [".nix"],
            doc = "A file containing an expression for a Nix derivation.",
        ),
        "pyproject_file": attr.label(allow_single_file = [".toml"]),
        "lock_file": attr.label(allow_single_file = [".lock"]),
        "quiet": attr.bool(),
    },
)

def _pip_package_impl(ctx):
    # HACK(danny): PyInfo doesn't let you pass absolute imports :(
    # we instead create a symlink to the store here
    store_symlink = ctx.actions.declare_symlink(ctx.label.name + "-store-link")

    ctx.actions.run_shell(outputs = [store_symlink], command = "ln -s {} {}".format(
        ctx.attr.store_path,
        store_symlink.path,
    ))

    # HACK(danny): for some unforunate reason, short_path returns ../ when operating in external
    # repositories. I don't know why. It breaks rules_python's assumptions though.
    fixed_path = store_symlink.short_path[3:]
    return [
        DefaultInfo(
            files = depset([store_symlink]),
            runfiles = ctx.runfiles(files = [store_symlink]),
        ),
        PyInfo(
            imports = depset([fixed_path + "/lib/python3.8/site-packages"]),
            transitive_sources = depset(),
        ),
    ]

pip_package = rule(
    implementation = _pip_package_impl,
    attrs = {
        "store_path": attr.string(
            doc = "nix store path of python package",
        ),
    },
    executable = False,
    test = False,
)
