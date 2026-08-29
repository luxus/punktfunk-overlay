# punktfunk-overlay

Deliberate NixOS delta on [unom/punktfunk](https://git.unom.io/unom/punktfunk): **unom main + required patches + Valve master gamescope + session module**. Experimental patches are opt-in and issue-tracked.

See **[AGENTS.md](./AGENTS.md)** for agent rules. Story lives in [GitHub issues](https://github.com/luxus/punktfunk-overlay/issues).

## What you get

| Piece | Role |
| --- | --- |
| `inputs.punktfunk-src` | Clean unom git (`flake = false`) |
| `patches/required/` | Always applied (empty on 0.28 — NixOS wrap detect is upstream) |
| `patches/experimental/` | Opt-in only (`services.punktfunk.overlay.experimentalPatches`) |
| `patches/archive/` | Retired; never applied |
| `packages/gamescope.nix` + unom `packaging/gamescope/patches/` + `gamescope-patches/` | Valve **master** + **all** unom HDR/capture patches; overlay extras only |
| `modules/` | unom NixOS module (from `punktfunk-src`) + `session.nix` (packages, PATH, desktopSession default) |
| `meta/patches.toml` | Every applied patch ↔ issue URL |

## Session references

- [KDE Plasma (KWin)](https://docs.punktfunk.unom.io/docs/kde)
- [Steam / gamescope](https://docs.punktfunk.unom.io/docs/gamescope)

Consumer user config: **hjem**, not home-manager.

## Consumer (luxusAi)

Single input — no vanilla unom flake beside this:

```nix
{
  inputs.punktfunk = {
    url = "path:/home/luxus/projects/punktfunk-overlay"; # or github:luxus/punktfunk-overlay
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # imports = [ inputs.punktfunk.nixosModules.default ];
  # services.punktfunk.host.enable = true;
  # services.punktfunk.host.users = [ "you" ];
  # Overlay defaults: host.desktopSession, VIDEO_SOURCE=virtual, CLIPBOARD=on, packages, PATH.
  # services.punktfunk.overlay.experimentalPatches = false; # default
}
```

Host-only knobs (users, gamestream, firewall, RUST_LOG) stay in the consumer.
Session/docs defaults live here (`modules/session.nix`), including `PUNKTFUNK_CLIPBOARD=on`.

## Bump unom (punktfunk main)

```bash
./scripts/update-punktfunk.sh              # flake update + required patch check
./scripts/update-punktfunk.sh --ref-tree   # also reset ~/projects/punktfunk → unom/main
./scripts/update-punktfunk.sh --build      # also nix build .#punktfunk-host
```

## Bump gamescope (Valve master)

```bash
./scripts/update-gamescope.sh              # pin tip rev + hash in packages/gamescope.nix
./scripts/update-gamescope.sh --check      # also verify gamescope-patches apply
./scripts/update-gamescope.sh --build      # also nix build .#punktfunk-gamescope
```

Note the bump on [issue #3](https://github.com/luxus/punktfunk-overlay/issues/3). Unom gamescope patches come from `punktfunk-src` ([#11](https://github.com/luxus/punktfunk-overlay/issues/11)).

## Experimental encode investigation

1. Measure baseline with experimental **off**.
2. Open a delta issue with numbers.
3. Add one `patches/experimental/*.patch` + `meta/patches.toml` entry + issue URL.
4. `services.punktfunk.overlay.experimentalPatches = true;`
5. Document proof; delete or promote.

## Skills

```bash
./scripts/setup-skills.sh   # ponytail + mattpocock/skills → .agents/skills/
```

Grok discovers `.agents/skills/` automatically.

## Checks

```bash
./scripts/check-patch-meta.sh
./scripts/check-gamescope-prs.sh   # needs network + gh
nix build .#punktfunk-host
nix build .#punktfunk-gamescope
```

## Layout

```
AGENTS.md
packages/gamescope.nix
modules/{default,session}.nix
patches/{required,experimental,archive}/
gamescope-patches/          # extras only; unom series is in punktfunk-src
meta/patches.toml
scripts/
.agents/skills/   # after setup-skills.sh
```
