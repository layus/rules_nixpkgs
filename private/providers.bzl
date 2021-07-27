"""
Providers used to pass data between nix-aware bazel rules.
"""

NixLibraryInfo = provider(
    doc = "Direct and transitive information passed between nix_cc rules",
    fields = {
        "info": "NixBuildInfo for the current rule",
        "deps": "depset of NixBuildInfos, not including the current rule's info",
    },
)

NixBuildInfo = provider(
    doc = "Named struct representing info about a single rule, used in NixLibraryInfo",
    fields = {
        # Nix import paths for filling -I <name>=<path>
        "name": "Name of nix build, same as rule name attribute",
        "nix_import": "File import for this .nix file",
        "extra_nix_files": "other .nix Files needed by build",
        "out_tree": "File of symlink output created by nix-build",
    },
)

NixPkgsInfo = provider(
    doc = "Information about the nix package repository. " +
          "Produced in nixpkgs_git_repository and consumed by nix_cc.",
    fields = {
        "nix_import": "File, default.nix of nixpkgs",
    },
)

NixDerivationInfo = provider(
    doc = "Produced by nix rules to signal to nix_deps_aspect that a " +
          "nix store path is depended on by this rule.",
    fields = {
        "out_tree": "File of bazel support TreeArtifact, or None",
        "store_path": "String, derivation's store path or symlink thereto",
    },
)

NixDepsInfo = provider(
    doc = "NixDeps is transitive information collected/produced by nix_deps_aspect. " +
          "Accumulated from NixDerivationInfo." +
          "Can be used to build docker containers with appropriate nix dependencies.",
    fields = {
        "out_trees": "Depset of Files, bazel support TreeArtifacts needed to reference store_paths",
        "store_paths": "Depset of store paths needed at runtime",
    },
)
