# Overlay session deltas on top of unom's nixos-module.
# Docs: https://docs.punktfunk.unom.io/docs/kde
#       https://docs.punktfunk.unom.io/docs/gamescope
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkDefault
    mkAfter
    optional
    ;

  cfg = config.services.punktfunk;
  system = pkgs.stdenv.hostPlatform.system;
  exp = cfg.overlay.experimentalPatches;

  pkg =
    name:
    let
      expName = "${name}-experimental";
    in
    if exp && self.packages.${system} ? ${expName} then
      self.packages.${system}.${expName}
    else
      self.packages.${system}.${name};
in
{
  options.services.punktfunk = {
    overlay = {
      experimentalPatches = mkEnableOption ''
        Use experimental overlay source patches (patches/experimental/).
        Off by default — only for issue-tracked investigation (e.g. encode latency).
      '';
    };
  };

  config = mkMerge [
    {
      # Force package defaults onto this flake (baseline or experimental).
      services.punktfunk.host.package = mkDefault (pkg "punktfunk-host");
      services.punktfunk.host.gamescopePackage = mkDefault self.packages.${system}.punktfunk-gamescope;
      services.punktfunk.client.package = mkDefault (pkg "punktfunk-client");
      services.punktfunk.web.package = mkDefault (pkg "punktfunk-web");
      services.punktfunk.scripting.package = mkDefault (pkg "punktfunk-scripting");

      # Desktop path defaults (KDE/virtual displays docs). Override for pure gamescope appliance.
      # https://docs.punktfunk.unom.io/docs/kde
      # unom leaves desktopSession off (appliance-safe); this overlay is for login desktops.
      services.punktfunk.host.settings.PUNKTFUNK_VIDEO_SOURCE = mkDefault "virtual";
      services.punktfunk.host.desktopSession = mkDefault true;
    }

    (mkIf cfg.host.enable {
      system.nixos.tags = [ "punktfunk-overlay" ] ++ optional exp "punktfunk-exp";

      systemd.user.services.punktfunk-host = {
        # steam → system profile; kscreen-doctor → libkscreen (often only in the user
        # profile / hjem, never on config.system.path). Without it KWin cannot set the
        # virtual output primary and the client can get wallpaper/black + wrong mode.
        path = mkAfter [
          config.system.path
          pkgs.kdePackages.libkscreen
        ];
      };
    })

    # Host `runner_command()` only checks FHS / SteamOS user paths, never PATH
    # (`/usr/bin/punktfunk-scripting` or `~/.local/bin/…`). Console plugin
    # installs use that seam, so NixOS looks uninstalled. SteamOS already uses
    # the ~/.local/bin wrapper — put the same link here.
    # https://github.com/luxus/punktfunk-overlay/issues/7
    (mkIf cfg.scripting.enable {
      systemd.user.tmpfiles.rules = [
        "L+ %h/.local/bin/punktfunk-scripting - - - - ${pkg "punktfunk-scripting"}/bin/punktfunk-scripting"
      ];
    })
  ];
}
