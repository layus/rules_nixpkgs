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
    doc = "Description of provider NixPkgs",
    fields = {
        "nix_import": "File, default.nix of nixpkgs",
    },
)
