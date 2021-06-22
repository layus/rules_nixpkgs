NixBuildInfo = provider(
    doc = "Nix import paths for filling -I <name>=<path>",
    fields = {
        "name": "Name of nix build, same as rule name attribute ",
        "nix_import": "File import for this .nix file",
        "extra_nix_files": "other .nix Files needed by build",
        "out_symlink": "File of symlink output created by nix-build",
    },
)

NixLibraryInfo = provider(
    doc = "Deps about a nix-build",
    fields = {
        "info": "NixBuildInfo",
        "deps": "depset of NixBuildInfos",
    },
)

NixPkgsInfo = provider(
    doc = "Nix repository's default.nix file",
    fields = {
        "nix_import": "File, default.nix of nixpkgs",
    },
)

NixDerivationInfo = provider(
    doc = "Metadata about the store path (e.g. /nix/store/abcdef) of a dep",
    fields = {
        "out_symlink": "File of bazel support symlink, or None",
        "store_path": "Derivation's store path",
    },
)

NixDepsInfo = provider(
    doc = "NixDeps is collected by an aspect",
    fields = {
        "out_symlinks": "Depset of bazel support dir Files needed to reference store_paths",
        "store_paths": "Depset of store paths needed at runtime",
    },
)
