# NixOS module entry: unom baseline module + overlay session wiring.
self: {
  imports = [
    (import ./nixos-module.nix self)
    (import ./session.nix self)
  ];
}
