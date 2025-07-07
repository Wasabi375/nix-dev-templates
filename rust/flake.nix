{
  description = "A simple rust dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils = {
        url = "github:numtide/flake-utils";
        inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [
            (import rust-overlay)
            (final: prev: {
                rustToolchain =
                    let
                        rust = prev.rust-bin;
                    in
                    if builtins.pathExists ./rust-toolchain.toml then
                        rust.fromRustupToolchainFile ./rust-toolchain.toml
                    else
                        rust.stable.default.override {
                            extensions = [ "rust-src" "rustfmt" "rust-analyzer" "clippy" ];
                        };
                    })
        ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
      in
      {
        devShells.default = with pkgs; mkShell {
          buildInputs = [
            openssl
            pkg-config
            rust-bin.stable.latest.default
            rust-analyzer
            cargo-deny
            cargo-edit
          ];

          shellHook = ''
          '';
        };
      }
    );
}
