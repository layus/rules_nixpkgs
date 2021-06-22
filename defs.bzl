load(
    "//nixpkgs:private/rules.bzl",
    _nix_bundleable = "nix_bundleable",
    _nix_cc = "nix_cc",
    _nix_deps_layer = "nix_deps_layer",
    _nix_package_repository = "nix_package_repository",
)
load(
    "//nixpkgs:private/aspects.bzl",
    _nix_deps_aspect = "nix_deps_aspect",
)

nix_cc = _nix_cc
nix_package_repository = _nix_package_repository
nix_bundleable = _nix_bundleable
nix_deps_aspect = _nix_deps_aspect
nix_deps_layer = _nix_deps_layer
