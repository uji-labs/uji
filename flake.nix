{
  description = "uji coding agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Provides the exact toolchain pinned in rust-toolchain.toml
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
    let
      systems = [
        # x86_64-darwin is gone: nixpkgs dropped Intel Macs in 26.11
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ rust-overlay.overlays.default ];
            }
          )
        );
      toolchain = pkgs: pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
      workspace = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).workspace.package;
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          rustPlatform = pkgs.makeRustPlatform {
            cargo = toolchain pkgs;
            rustc = toolchain pkgs;
          };
        in
        {
          default = rustPlatform.buildRustPackage {
            pname = "uji";
            inherit (workspace) version;
            # only what the build reads, so editing docs, README or this flake
            # doesn't force everyone to rebuild uji
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./Cargo.toml
                ./Cargo.lock
                ./crates
                ./lua
              ];
            };
            cargoLock = {
              lockFile = ./Cargo.lock;
              # lets Cargo.lock gain git dependencies without hand-written hashes
              allowBuiltinFetchGit = true;
            };
            cargoBuildFlags = [
              "--package"
              "uji"
            ];
            # the test suite runs separately (crates/tests); keep installs fast
            doCheck = false;
            meta = {
              description = "uji coding agent";
              homepage = workspace.repository;
              license = pkgs.lib.licenses.gpl3Plus;
              mainProgram = "uji";
            };
          };
        }
      );

      # programs.uji for home-manager, and the helpers pack modules use
      homeModules.default = import ./nix/home-manager.nix self;
      homeManagerModules = self.homeModules;
      lib = import ./nix/lib.nix { inherit (nixpkgs) lib; };

      # `nix flake check` builds the package
      checks = forAllSystems (pkgs: {
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          # everything the justfile uses, plus what the build links against
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
          packages = [
            ((toolchain pkgs).override {
              extensions = [
                "rust-src"
                "rust-analyzer"
              ];
            })
            pkgs.just
            pkgs.ast-grep
            pkgs.stylua
            pkgs.lua54Packages.luacheck
            pkgs.selene
            pkgs.mdbook
          ];
        };
      });
    };
}
