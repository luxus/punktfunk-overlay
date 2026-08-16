# NixOS module entry: unom's module from punktfunk-src + overlay session wiring.
# Do not fork the unom module — bump the flake input to pick up their changes.
self: {
  imports = [
    (import (self.inputs.punktfunk-src + "/packaging/nix/nixos-module.nix") self)
    (import ./session.nix self)
  ];
}
