# punktfunk-overlay

Public Nix overlay for [unom/punktfunk](https://git.unom.io/unom/punktfunk): **upstream source + ordered local patches**, so lea (and other hosts) can stay aligned with upstream without carrying a long-lived source fork.

## What this is

| Piece | Role |
| --- | --- |
| `inputs.punktfunk-src` | Clean upstream git (flake = false) |
| `patches/` | `git format-patch` series applied with `pkgs.applyPatches` |
| `packages.*` | Crane builds from the **patched** tree (same as upstream packaging) |
| `nixosModules.default` | Upstream NixOS module pointed at those packages |

## Consumer (e.g. luxusAi)

```nix
{
  inputs.punktfunk-overlay.url = "github:luxus/punktfunk-overlay";
  # optional: share nixpkgs
  # inputs.punktfunk-overlay.inputs.nixpkgs.follows = "nixpkgs";

  # Was: inputs.punktfunk.url = "path:/…/punktfunk";
  # Now:
  #   imports = [ inputs.punktfunk-overlay.nixosModules.default ];
  #   # package defaults come from the overlay flake
}
```

If your config still names the input `punktfunk`:

```nix
punktfunk = {
  url = "github:luxus/punktfunk-overlay";
  inputs.nixpkgs.follows = "nixpkgs";
};
# imports = [ inputs.punktfunk.nixosModules.default ];
```

## Bump upstream

```bash
nix flake update punktfunk-src
# rebuild / nh os switch
```

If a patch fails to apply after a bump, refresh the series from a temporary checkout:

```bash
git clone https://git.unom.io/unom/punktfunk /tmp/pf && cd /tmp/pf
# cherry-pick or re-implement fixes, then:
git format-patch origin/main -o /path/to/punktfunk-overlay/patches
```

## Current patch series

See `patches/0001-…` through `0008-…` — Nix packaging fixes, KWin Nix wrap detection, steam on host PATH, HDR colour/channel-order knobs, etc.

## Local drop-ins

Session-specific systemd drop-ins (e.g. `~/.config/systemd/user/punktfunk-host.service.d/extra-path.conf`) stay on the machine; the module PATH fix lands in-tree via patch `0008` so a clean deploy does not need the drop-in after rebuild.
