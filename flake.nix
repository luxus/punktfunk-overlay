{
  description = "NixOS overlay for unom/punktfunk — unom main + deliberate deltas";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bun2nix = {
      url = "github:nix-community/bun2nix?ref=2.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Bump: nix flake update punktfunk-src
    punktfunk-src = {
      url = "git+https://git.unom.io/unom/punktfunk";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      rust-overlay,
      bun2nix,
      punktfunk-src,
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      lib = nixpkgs.lib;

      listPatches =
        dir:
        let
          entries = builtins.readDir dir;
          names = builtins.attrNames entries;
          patches = builtins.filter (n: lib.hasSuffix ".patch" n) names;
        in
        map (n: dir + "/${n}") (lib.sort (a: b: a < b) patches);

      requiredPatches = listPatches ./patches/required;
      experimentalPatches = listPatches ./patches/experimental;

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

      toolchainFor = pkgs: pkgs.rust-bin.fromRustupToolchainFile (punktfunk-src + "/rust-toolchain.toml");
      craneLibFor = pkgs: (crane.mkLib pkgs).overrideToolchain toolchainFor;

      version =
        (builtins.fromTOML (builtins.readFile (punktfunk-src + "/Cargo.toml"))).workspace.package.version;

      mkPackages =
        system: extraPatches: srcName:
        let
          pkgs = pkgsFor system;
          src = pkgs.applyPatches {
            name = srcName;
            src = punktfunk-src;
            patches = requiredPatches ++ extraPatches;
          };
          pf = pkgs.callPackage (src + "/packaging/nix/packages.nix") {
            craneLib = craneLibFor pkgs;
            inherit src version;
            bun2nix = bun2nix.packages.${system}.default;
          };
        in
        pf;

      packagesFor =
        system:
        let
          pkgs = pkgsFor system;
          baseline = mkPackages system [ ] "punktfunk-src-baseline";
          experimental =
            if experimentalPatches == [ ] then
              baseline
            else
              mkPackages system experimentalPatches "punktfunk-src-experimental";
          gamescope = pkgs.callPackage ./packages/gamescope.nix {
            patchDir = ./gamescope-patches;
            manifestRewriter = punktfunk-src + "/packaging/gamescope/rewrite-wsi-layer-manifest.py";
          };
          withExpAliases = lib.mapAttrs' (name: value: {
            name = "${name}-experimental";
            value = experimental.${name};
          }) experimental;
        in
        baseline
        // withExpAliases
        // {
          punktfunk-gamescope = gamescope;
          default = baseline.punktfunk-host;
        };
    in
    {
      packages = forAllSystems packagesFor;

      nixosModules.default = import ./modules/default.nix self;
      nixosModules.punktfunk = self.nixosModules.default;

      checks = forAllSystems (system: {
        inherit (self.packages.${system}) punktfunk-host punktfunk-tray;
      });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);

      # Lightweight dev shell for meta scripts + formatting.
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixfmt-rfc-style
              pkgs.gh
              pkgs.git
            ];
          };
        }
      );
    };
}
