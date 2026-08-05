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
    # Upstream source. Bump: nix flake update punktfunk-src
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

      # Ordered patch series (git format-patch against unom/main).
      overlayPatches = [
        ./patches/0001-fix-nix-regenerate-web-bun.nix-stop-gamescope.nix-de.patch
        ./patches/0002-feat-encode-nvenc-name-who-did-the-RGB-YUV-conversio.patch
        ./patches/0003-fix-host-colour-apply-the-colour-override-to-the-han.patch
        ./patches/0004-test-capture-hdr-knob-to-flip-the-10-bit-PQ-channel-.patch
        ./patches/0005-fix-capture-hdr-offer-the-10-bit-channel-order-produ.patch
        ./patches/0006-fix-vdisplay-detect-NixOS-wrapped-compositors-via-pr.patch
        ./patches/0007-fix-nix-strip-host-target-from-package-src.patch
        ./patches/0008-fix-nix-put-system-profile-on-host-service-PATH-for-.patch
        ./patches/0009-feat-nix-gamescope-track-Valve-master-2271-is-upstr.patch
      ];

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

      toolchainFor =
        pkgs: pkgs.rust-bin.fromRustupToolchainFile (punktfunk-src + "/rust-toolchain.toml");
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
          # packaging/*.nix after patches (includes packages.nix src clean + gamescope.nix fix)
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
        };
    in
    {
      packages = forAllSystems packagesFor;

      # Vendored module (from patched tree) — no import-from-derivation on `imports`.
      # Package defaults resolve via `self.packages.${system}` like upstream.
      nixosModules.default = import ./modules/nixos-module.nix self;
      nixosModules.punktfunk = self.nixosModules.default;

      checks = forAllSystems (system: {
        inherit (self.packages.${system}) punktfunk-host punktfunk-tray;
      });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
