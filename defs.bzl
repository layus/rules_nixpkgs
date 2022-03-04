load(
    "//private:rules.bzl",
    _nix_bundleable = "nix_bundleable",
    _nix_cc = "nix_cc",
    _nix_deps_layer = "nix_deps_layer",
    _nix_package_repository = "nix_package_repository",
)
load(
    "//private:aspects.bzl",
    _nix_deps_aspect = "nix_deps_aspect",
)

_SUPPORT_NIX = "@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix"

def nix_cc(target_compatible_with = [], **kwargs):
    _nix_cc(target_compatible_with = [_SUPPORT_NIX] + target_compatible_with, **kwargs)

nix_package_repository = _nix_package_repository
nix_bundleable = _nix_bundleable
nix_deps_aspect = _nix_deps_aspect
nix_deps_layer = _nix_deps_layer
