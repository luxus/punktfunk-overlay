#!/usr/bin/env bash
# Bump packages/gamescope.nix to ValveSoftware/gamescope master tip.
#
# Usage:
#   ./scripts/update-gamescope.sh           # pin rev + hash + version date
#   ./scripts/update-gamescope.sh --check   # also apply unom series + gamescope-patches/ extras
#   ./scripts/update-gamescope.sh --build   # also nix build .#punktfunk-gamescope
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GS_NIX="$ROOT/packages/gamescope.nix"
EXTRA_PATCH_DIR="$ROOT/gamescope-patches"
REF_TREE_PATH="${HOME}/projects/punktfunk"
OWNER=ValveSoftware
REPO=gamescope
BRANCH=master

CHECK=0
BUILD=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --build) BUILD=1 ;;
    -h | --help)
      sed -n '2,8p' "$0"
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
need curl
need nix
need python3

echo "→ ${OWNER}/${REPO}@${BRANCH} tip …"
API="$(curl -fsSL "https://api.github.com/repos/${OWNER}/${REPO}/commits/${BRANCH}")"
REV="$(printf '%s' "$API" | python3 -c 'import sys,json; print(json.load(sys.stdin)["sha"])')"
DATE="$(printf '%s' "$API" | python3 -c 'import sys,json; print(json.load(sys.stdin)["commit"]["committer"]["date"][:10])')"
VERSION="0-unstable-${DATE}"
SHORT="${REV:0:7}"

OLD_REV="$(
  python3 - "$GS_NIX" <<'PY'
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'gamescopeRev = "([0-9a-f]+)"', t)
print(m.group(1) if m else "")
PY
)"
if [[ "$OLD_REV" == "$REV" ]]; then
  echo "already at ${SHORT} (${DATE})"
  exit 0
fi

echo "→ prefetch src (submodules) ${SHORT} …"
HASH=""
if command -v nix-prefetch-github >/dev/null 2>&1; then
  PREF="$(nix-prefetch-github --rev "$REV" --fetch-submodules "$OWNER" "$REPO" 2>/dev/null || true)"
  HASH="$(
    printf '%s' "$PREF" | python3 -c '
import sys, json, re
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit
try:
    d = json.loads(raw)
    h = d.get("hash") or d.get("sha256") or ""
    print(h)
except Exception:
    m = re.search(r"sha256-[A-Za-z0-9+/=]+", raw)
    print(m.group(0) if m else "")
'
  )" || true
  if [[ -n "${HASH:-}" && "$HASH" != sha256-* ]]; then
    HASH="$(nix hash to-sri --type sha256 "$HASH")"
  fi
fi
if [[ -z "${HASH:-}" ]]; then
  HASH="$(
    nix flake prefetch --json "github:${OWNER}/${REPO}?rev=${REV}&submodules=1" \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["hash"])'
  )"
fi
if [[ -z "${HASH:-}" ]]; then
  echo "error: could not compute src hash" >&2
  exit 1
fi

echo "  ${OLD_REV:0:7} → ${REV}"
echo "  version  $VERSION"
echo "  hash     $HASH"

python3 - "$GS_NIX" "$REV" "$VERSION" "$HASH" <<'PY'
import pathlib, re, sys

path, rev, version, h = sys.argv[1:5]
text = pathlib.Path(path).read_text()
text2, n1 = re.subn(r'gamescopeRev = "[0-9a-f]+"', f'gamescopeRev = "{rev}"', text, count=1)
text2, n2 = re.subn(r'version = "0-unstable-[0-9-]+"', f'version = "{version}"', text2, count=1)

def repl_src(m: re.Match[str]) -> str:
    block = m.group(0)
    block2, n = re.subn(r'hash = "sha256-[^"]+"', f'hash = "{h}"', block, count=1)
    if n != 1:
        raise SystemExit("error: could not find hash= inside gamescope src block")
    return block2

text3, n3 = re.subn(
    r'src = fetchFromGitHub \{[^}]*owner = "ValveSoftware"[^}]*\};',
    repl_src,
    text2,
    count=1,
    flags=re.S,
)
if n1 != 1 or n2 != 1 or n3 != 1:
    raise SystemExit(f"error: expected 1 edit each (rev={n1} ver={n2} hash={n3})")
pathlib.Path(path).write_text(text3)
print(f"→ wrote {path}")
PY

if [[ "$CHECK" -eq 1 ]]; then
  echo "→ patch --check against ${SHORT} …"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  git clone --filter=blob:none --no-checkout "https://github.com/${OWNER}/${REPO}.git" "$work/gs" >/dev/null
  git -C "$work/gs" fetch --depth 1 origin "$REV" >/dev/null
  git -C "$work/gs" checkout --detach FETCH_HEAD >/dev/null

  pf_rev="$(
    python3 - "$ROOT/flake.lock" <<'PY'
import json, pathlib, sys
print(json.loads(pathlib.Path(sys.argv[1]).read_text())["nodes"]["punktfunk-src"]["locked"]["rev"])
PY
  )"
  unom_patches=""
  if [[ -d "$REF_TREE_PATH/.git" && "$(git -C "$REF_TREE_PATH" rev-parse HEAD)" == "$pf_rev" ]]; then
    unom_patches="$REF_TREE_PATH/packaging/gamescope/patches"
  else
    git clone --filter=blob:none --no-checkout "https://git.unom.io/unom/punktfunk" "$work/pf" >/dev/null
    git -C "$work/pf" fetch --depth 1 origin "$pf_rev" >/dev/null
    git -C "$work/pf" checkout --detach FETCH_HEAD >/dev/null
    unom_patches="$work/pf/packaging/gamescope/patches"
  fi

  fail=0
  shopt -s nullglob
  # Apply (not just --check) so later hunks see earlier ones, matching the nix apply order.
  for p in "$unom_patches"/*.patch "$EXTRA_PATCH_DIR"/*.patch; do
    [[ -f "$p" ]] || continue
    if git -C "$work/gs" apply "$p" 2>/dev/null; then
      echo "  ok   $(basename "$p")"
    else
      echo "  FAIL $(basename "$p")" >&2
      git -C "$work/gs" apply --check "$p" 2>&1 | sed 's/^/       /' || true
      fail=1
    fi
  done
  [[ "$fail" -eq 0 ]] || exit 1
fi

if [[ "$BUILD" -eq 1 ]]; then
  echo "→ nix build .#punktfunk-gamescope …"
  (cd "$ROOT" && nix build ".#punktfunk-gamescope" -L)
fi

echo "done — consider noting on issue #3"
echo "  rev $REV"
