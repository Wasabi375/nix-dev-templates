{
    description = "A Nix-flake-based Rust development environment";

    inputs = {
        nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/*.tar.gz";
        rust-overlay = {
            url = "github:oxalica/rust-overlay";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        parts = {
            url = "github:hercules-ci/flake-parts";
            inputs.nixpkgs-lib.follows = "nixpkgs";
        };
        nix-filter.url = "github:numtide/nix-filter";
        crane.url = "github:ipetkov/crane";
   };

    outputs = inputs@{ self, nixpkgs, rust-overlay, parts, nix-filter, crane}:
    parts.lib.mkFlake { inherit inputs; } {
        systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
        perSystem = { self', lib, system, ... }: 
        let 
            # use the rust overlay iff there is a rust-toolchain file present
            use-rust-overlay = false;
            overlays =  if builtins.pathExists ./rust-toolchain.toml || use-rust-overlay then
                [(import rust-overlay)] 
            else [];

            pkgs = import nixpkgs { inherit system; overlays = overlays; };

            rust-toolchain = if builtins.pathExists ./rust-toolchain.toml then 
                pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml
            else if use-rust-overlay then
                pkgs.rust-bin.stable.latest
            else null;

            cargo_toml = if builtins.pathExists ./Cargo.toml then builtins.fromTOML( builtins.readFile ./Cargo.toml) else null;
            dev_packages = with pkgs; [
                pkg-config
                cargo
                rustc
                cargo-deny
                cargo-edit
                cargo-watch
                rust-analyzer
                rustfmt
            ];
            craneLib = if rust-toolchain != null then 
                (crane.mkLib pkgs).overrideToolchain rust-toolchain
                else crane.mkLib pkgs;
            craneArgs = {
                pname = cargo_toml.package.name;
                version = cargo_toml.package.version;

                src = nix-filter.lib.filter {
                    root = ./.;
                    include = [
                        ./src
                        ./Cargo.toml
                        ./Cargo.lock
                        ./rust-toolchain.toml
                    ];
                };

                nativeBuildInputs = [];

                buildInputs = [];

                runtimeDependencies = [];
            };
            cargoArtifacts = craneLib.buildDepsOnly craneArgs;
            finalRustPkg = if builtins.pathExists ./Cargo.toml
                then craneLib.buildPackage ( craneArgs // { inherit cargoArtifacts; })
                else null;

            noGitFlake = pkgs.writeShellApplication {
                name = "flake-mark-no-git";
                text = ''
                    echo "git add flake.nix flake.lock" > .envrc
                    if [ -f "rust-toolchain.toml" ]; then echo "git add rust-toolchain.toml" >> .envrc; fi
                    echo "use flake" >> .envrc
                    if [ -f "rust-toolchain.toml" ]; then echo "git restore --staged rust-toolchain.toml" >> .envrc; fi
                    echo "git restore --staged flake.nix flake.lock" >> .envrc
                '';
            };
            gitFlake = pkgs.writeShellApplication {
                name = "flake-mark-git";
                text = ''echo "use flake" > .envrc'';
            };
            uninitializedPacakge = pkgs.writeShellApplication {
                name = "missing-package";
                text = "echo 'package source missing'";
            };
            finalPkg = if finalRustPkg != null then finalRustPkg else uninitializedPacakge;
        in
        {
            checks.finalPkg = finalPkg;
            packages.default = finalPkg;

            devShells.default = pkgs.mkShell {
                packages = dev_packages ++ [ noGitFlake gitFlake];
                LD_LIBRARY_PATH = if finalRustPkg != null 
                    then lib.makeLibraryPath (__concatMap (d: d.runtimeDependencies) (__attrValues self'.checks))
                    else "";

                inputsFrom = [ finalPkg ];
            };
        };
    };
}
