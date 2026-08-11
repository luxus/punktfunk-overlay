#!/usr/bin/env bash
# Every applied patch file must be listed in meta/patches.toml with an issue URL.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
META="$ROOT/meta/patches.toml"

if [[ ! -f "$META" ]]; then
  echo "error: missing $META" >&2
  exit 1
fi

fail=0

collect_patches() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.patch' | sort
}

# Paths relative to repo root as stored in meta (file = "…")
relpath() {
  local f="$1"
  echo "${f#"$ROOT"/}"
}

declare -A meta_files=()
while IFS= read -r line; do
  if [[ "$line" =~ ^file[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
    meta_files["${BASH_REMATCH[1]}"]=1
  fi
done <"$META"

# Every applied patch must be in meta
for dir in patches/required patches/experimental gamescope-patches; do
  while IFS= read -r abs; do
    [[ -z "$abs" ]] && continue
    rel="$(relpath "$abs")"
    if [[ -z "${meta_files[$rel]+x}" ]]; then
      echo "error: patch not in meta/patches.toml: $rel" >&2
      fail=1
    fi
  done < <(collect_patches "$ROOT/$dir")
done

# Every meta file= must exist; issue= must be non-empty for non-archive
# (simple line scan)
file=""
issue=""
tier=""
flush() {
  if [[ -z "$file" ]]; then
    return 0
  fi
  if [[ ! -f "$ROOT/$file" ]]; then
    echo "error: meta lists missing file: $file" >&2
    fail=1
  fi
  if [[ "$tier" != "archive" && -z "$issue" ]]; then
    echo "error: meta entry for $file missing issue" >&2
    fail=1
  fi
  if [[ "$tier" != "archive" && "$issue" != https://github.com/* ]]; then
    echo "error: meta entry for $file issue must be a github.com URL (got: $issue)" >&2
    fail=1
  fi
  file=""
  issue=""
  tier=""
}

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^\[\[patch\]\] ]]; then
    flush
    continue
  fi
  if [[ "$line" =~ ^file[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
    file="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^issue[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
    issue="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^tier[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
    tier="${BASH_REMATCH[1]}"
  fi
done <"$META"
flush

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "check-patch-meta: ok"
