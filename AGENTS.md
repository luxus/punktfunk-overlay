# AGENTS.md — punktfunk-overlay

Behavioral rules for humans and coding agents working in this repository.

## Product / architecture laws

- **Do not preserve backward compatibility.** Remove obsolete paths instead of adding compatibility layers, fallbacks, or migrations.
- **Simplest implementation** that fully meets current requirements. No speculative abstractions, configuration, or indirection.
- **Grow in layers.** Smallest end-to-end that works first; add each new capability on top of a product that already works. Never trade a working product for unfinished complexity.
- **Modular concerns.** Packages, session module, gamescope package, and experimental patches stay separate.
- Prefer **established, maintained** tools when they reduce complexity. Do not reimplement common functionality without a clear reason.
- **Lean on dependencies already in the project** before writing new code or adding packages. Check docs before assuming a gap.
- **Long-term decisions.** No temporary stopgaps meant to be replaced later.

## Source of truth

- **Upstream punktfunk:** [unom/punktfunk](https://git.unom.io/unom/punktfunk) `main`.
- **This repo:** only the deliberate delta (required patches, gamescope package, session module, experiments).
- **No long-lived punktfunk fork.** Reference tree: `~/projects/punktfunk` tracks unom `main` only (read / format-patch / re-audit).
- **Session authority:** [KDE docs](https://docs.punktfunk.unom.io/docs/kde), [gamescope docs](https://docs.punktfunk.unom.io/docs/gamescope).
- Consumer user config on lea: **hjem**, not home-manager.

## Patches and tiers

| Tier | Path | Default applied? |
| --- | --- | --- |
| `required` | `patches/required/` | yes |
| `experimental` | `patches/experimental/` | no (opt-in) |
| `gamescope` | `gamescope-patches/` | yes (on `punktfunk-gamescope` only) |
| `archive` | `patches/archive/` | never |

Rules:

- Every on-disk patch under applied dirs **must** appear in `meta/patches.toml` with an **issue URL**.
- **Experimental off by default.** Enable via `services.punktfunk.overlay.experimentalPatches` or package override.
- **No colour/VUI diagnostic patches in default** without a colour-specific issue and proof.
- Prefer **session.nix** / package Nix for NixOS wiring over patching unom source when possible.

## Issue story (hard rule)

Every intentional change has a GitHub issue on `luxus/punktfunk-overlay` (or updates one) recording:

1. **Problem**
2. **Decision / why**
3. **Proof** (commands, logs, measurements)
4. **Upstream disposition:** `none` | `unom-issue` | `unom-pr` | `gamescope-pr` (+ links)

For every kept delta, ask: should this be an **unom** or **Valve gamescope** issue/PR? Prefer upstream when general; overlay-only when NixOS/hjem-specific or temporary experiment.

## Upstream checklist

1. Already fixed on unom/Valve main? → drop.
2. Useful to all distros? → unom issue/PR.
3. Compositor capture? → gamescope PR + `gamescope_prs` in meta.
4. NixOS wrap / hjem / packaging only? → overlay-only, still issue + proof.
5. Temporary experiment? → experimental tier; delete when done.

## Encode / performance investigation

1. Measure **baseline** (required only, no experimental).
2. Open an issue with numbers.
3. One experimental patch at a time; document before/after in the issue.
4. Promote to required or upstream only with proof.

## Skills

Project skills live under `.agents/skills/` (vendored from [ponytail](https://github.com/DietrichGebert/ponytail) and [mattpocock/skills](https://github.com/mattpocock/skills)).

- Use **ponytail** when tempted to add layers: delete, simplify, YAGNI.
- Leave `ponytail:` comments only for deliberate deferrals — and **issue-track** that debt.

## Pre-commit / verification

Before claiming done:

- `scripts/check-patch-meta.sh` passes.
- Nix formatted (`nix fmt` / treefmt when configured).
- Relevant packages build when you claim they build (`nix build .#punktfunk-host`, etc.).

## Surgical changes

Touch only what the issue requires. No drive-by refactors, no “while I’m here” compatibility shims.
