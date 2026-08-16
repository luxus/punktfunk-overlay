#!/usr/bin/env bash
# Bump flake input punktfunk-src to unom/punktfunk main tip and verify required patches apply.
#
# Usage:
#   ./scripts/update-punktfunk.sh            # nix flake update + patch check
#   ./scripts/update-punktfunk.sh --build    # also nix build .#punktfunk-host (slow)
#   ./scripts/update-punktfunk.sh --ref-tree # also reset ~/projects/punktfunk to unom/main
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQ_DIR="$ROOT/patches/required"
REF_TREE_PATH="${HOME}/projects/punktfunk"
UNOM_URL="https://git.unom.io/unom/punktfunk"

BUILD=0
SYNC_REF=0
for arg in "$@"; do
  case "$arg" in
    --build) BUILD=1 ;;
    --ref-tree) SYNC_REF=1 ;;
    -h | --help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 1
      ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || {
  echo "error: need $1" >&2
  exit 1
}; }
need nix
need git
need python3

read_rev() {
  python3 - "$ROOT/flake.lock" <<'PY'
import json, pathlib, sys
lock = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(lock["nodes"]["punktfunk-src"]["locked"]["rev"])
PY
}

old_rev="$(read_rev 2>/dev/null || true)"

echo "→ nix flake update punktfunk-src …"
(cd "$ROOT" && nix flake update punktfunk-src)

new_rev="$(read_rev)"
SHORT="${new_rev:0:7}"
if [[ -n "${old_rev:-}" && "$old_rev" == "$new_rev" ]]; then
  echo "punktfunk-src already at ${SHORT}"
else
  echo "  ${old_rev:-?} → ${new_rev}"
fi

echo "→ check required patches on ${SHORT} …"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone --filter=blob:none --no-checkout "$UNOM_URL" "$work/pf" >/dev/null
git -C "$work/pf" fetch --depth 1 origin "$new_rev" >/dev/null
git -C "$work/pf" checkout --detach FETCH_HEAD >/dev/null

fail=0
shopt -s nullglob
patches=("$REQ_DIR"/*.patch)
if [[ ${#patches[@]} -eq 0 ]]; then
  echo "  (no required patches)"
else
  for p in "${patches[@]}"; do
    if git -C "$work/pf" apply --check "$p" 2>/dev/null; then
      echo "  ok   $(basename "$p")"
    else
      echo "  FAIL $(basename "$p")" >&2
      git -C "$work/pf" apply --check "$p" 2>&1 | sed 's/^/       /' || true
      fail=1
    fi
  done
fi
if [[ "$fail" -ne 0 ]]; then
  echo "error: required patches do not apply — refresh from a unom checkout:" >&2
  echo "  git -C ~/projects/punktfunk fetch unom && git -C ~/projects/punktfunk checkout unom/main" >&2
  echo "  # re-implement / format-patch into patches/required/" >&2
  exit 1
fi

echo "→ check unom + overlay gamescope patches on Valve pin …"
gs_rev="$(
  python3 - "$ROOT/packages/gamescope.nix" <<'PY'
import re, pathlib, sys
m = re.search(r'gamescopeRev = "([0-9a-f]+)"', pathlib.Path(sys.argv[1]).read_text())
print(m.group(1) if m else "")
PY
)"
if [[ -z "$gs_rev" ]]; then
  echo "error: could not read gamescopeRev from packages/gamescope.nix" >&2
  exit 1
fi
git clone --filter=blob:none --no-checkout "https://github.com/ValveSoftware/gamescope.git" "$work/gs" >/dev/null
git -C "$work/gs" fetch --depth 1 origin "$gs_rev" >/dev/null
git -C "$work/gs" checkout --detach FETCH_HEAD >/dev/null
gs_fail=0
shopt -s nullglob
for p in "$work/pf/packaging/gamescope/patches"/*.patch "$ROOT/gamescope-patches"/*.patch; do
  [[ -f "$p" ]] || continue
  if git -C "$work/gs" apply "$p" 2>/dev/null; then
    echo "  ok   $(basename "$p")"
  else
    echo "  FAIL $(basename "$p")" >&2
    git -C "$work/gs" apply --check "$p" 2>&1 | sed 's/^/       /' || true
    gs_fail=1
  fi
done
if [[ "$gs_fail" -ne 0 ]]; then
  echo "error: gamescope patches do not apply on ${gs_rev:0:7} — rebase extras or bump the Valve pin" >&2
  exit 1
fi

if [[ "$SYNC_REF" -eq 1 ]]; then
  if [[ -d "$REF_TREE_PATH/.git" ]]; then
    echo "→ sync reference tree $REF_TREE_PATH → unom/main …"
    if ! git -C "$REF_TREE_PATH" remote get-url unom >/dev/null 2>&1; then
      git -C "$REF_TREE_PATH" remote add unom "$UNOM_URL"
    fi
    git -C "$REF_TREE_PATH" fetch unom
    git -C "$REF_TREE_PATH" checkout -B main unom/main
    echo "  $(git -C "$REF_TREE_PATH" log -1 --oneline)"
  else
    echo "warn: no git repo at $REF_TREE_PATH — skip --ref-tree" >&2
  fi
fi

if [[ "$BUILD" -eq 1 ]]; then
  echo "→ nix build .#punktfunk-host …"
  (cd "$ROOT" && nix build ".#punktfunk-host" -L)
fi

echo "done — punktfunk-src $new_rev"
