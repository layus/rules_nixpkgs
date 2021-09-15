with import <nixpkgs> {};
let
  src = fetchFromGitHub {
    owner = "nix-community";
    repo = "poetry2nix";
    rev = "2a0564d56408a09a33b6010484378b2e663351e7";
    sha256 = "10c0z8mkz18amqx964yky4a3czampry6mfvwpbh8d8n1aj1c0kv3";
  };
in
  with import "${src.out}/overlay.nix" pkgs pkgs;
  let
    packages = poetry2nix.mkPoetryPackages {
      projectDir = ./.;
      preferWheels = true;
    };

    pyToolchains = ''

load("@rules_python//python:defs.bzl", "py_runtime", "py_runtime_pair")

py_runtime(
    name = "python3_runtime",
    interpreter_path = "${packages.python}/bin/python",
    python_version = "PY3",
    visibility = ["//visibility:public"],
)

py_runtime_pair(
    name = "runtime_pair",
    py3_runtime = ":python3_runtime",
)

toolchain(
    name = "py_toolchain",
    target_compatible_with = ["@platforms//os:linux"],
    toolchain = ":runtime_pair",
    toolchain_type = "@bazel_tools//tools/python:toolchain_type",
)
    '';

    concatBazelRules = lib.lists.foldr (pipPackage: buildFile:
        buildFile + ''

pip_package(
    name = "${pipPackage.pname}",
    store_path = "${pipPackage.out}",
    visibility = ["//visibility:public"],
)
        ''
    ) ''load("@rules_nixpkgs//private:pip_repo.bzl", "pip_package")'';

  in
  pkgs.writeTextFile {
    name = "BUILD.bazel";
    text = (concatBazelRules packages.poetryPackages) + pyToolchains;
  }
