{
  description = "NixOS overlay/patches for unom/punktfunk — stay on upstream, carry local fixes";

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
    # Upstream source (not a flake input for packages — we patch then build).
    # Bump with: nix flake update punktfunk-src
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

      # Ordered patch series (git format-patch unom/main..local).
      # Add new fixes here; re-export stays stable for consumers.
      overlayPatches = [
        ./patches/0001-fix-nix-regenerate-web-bun.nix-stop-gamescope.nix-de.patch
        ./patches/0002-feat-encode-nvenc-name-who-did-the-RGB-YUV-conversio.patch
        ./patches/0003-fix-host-colour-apply-the-colour-override-to-the-han.patch
        ./patches/0004-test-capture-hdr-knob-to-flip-the-10-bit-PQ-channel-.patch
        ./patches/0005-fix-capture-hdr-offer-the-10-bit-channel-order-produ.patch
        ./patches/0006-fix-vdisplay-detect-NixOS-wrapped-compositors-via-pr.patch
        ./patches/0007-fix-nix-strip-host-target-from-package-src.patch
        ./patches/0008-fix-nix-put-system-profile-on-host-service-PATH-for-.patch
      ];

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

      packagesFor =
        system:
        let
          pkgs = pkgsFor system;
          patchedSrc = pkgs.applyPatches {
            name = "punktfunk-src-patched";
            src = punktfunk-src;
            patches = overlayPatches;
          };
          pf = pkgs.callPackage (patchedSrc + "/packaging/nix/packages.nix") {
            craneLib = craneLibFor pkgs;
            src = patchedSrc;
            inherit version;
            bun2nix = bun2nix.packages.${system}.default;
          };
          gamescope = pkgs.callPackage (patchedSrc + "/packaging/nix/gamescope.nix") {
            patchDir = patchedSrc + "/packaging/gamescope/patches";
          };
        in
        pf
        // {
          punktfunk-gamescope = gamescope;
          default = pf.punktfunk-host;
          # Expose patched tree for debugging / further packaging
          punktfunk-src-patched = patchedSrc;
        };

      # self-shaped attrset the upstream nixos-module expects (`self.packages.${system}....`).
      moduleSelfFor =
        system:
        {
          packages.${system} = packagesFor system;
        };
    in
    {
      packages = forAllSystems packagesFor;

      # Drop-in replacement for inputs.punktfunk.nixosModules.default
      nixosModules.default =
        { pkgs, ... }:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          imports = [
            (import ((packagesFor system).punktfunk-src-patched + "/packaging/nix/nixos-module.nix") (
              moduleSelfFor system
            ))
          ];
        };

      # Convenience alias
      nixosModules.punktfunk = self.nixosModules.default;

      checks = forAllSystems (
        system:
        let
          pf = self.packages.${system};
        in
        {
          inherit (pf) punktfunk-host punktfunk-tray;
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
