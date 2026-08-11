#!/usr/bin/env bash
# Fail if any meta/patches.toml gamescope_prs entry is already merged (time to drop the patch).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
META="$ROOT/meta/patches.toml"

if [[ ! -f "$META" ]]; then
  echo "error: missing $META" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI required for check-gamescope-prs" >&2
  exit 1
fi

fail=0
file=""

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^file[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
    file="${BASH_REMATCH[1]}"
  fi
  # gamescope_prs = [ "https://github.com/ValveSoftware/gamescope/pull/2270", ... ]
  if [[ "$line" =~ gamescope_prs ]]; then
    while [[ "$line" =~ https://github.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; do
      owner="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]}"
      num="${BASH_REMATCH[3]}"
      state="$(gh api "repos/${owner}/${repo}/pulls/${num}" --jq '.state + ":" + (.merged|tostring)' 2>/dev/null || echo "error:unknown")"
      echo "check: $file -> ${owner}/${repo}#${num} => $state"
      if [[ "$state" == merged:true || "$state" == closed:true ]]; then
        # closed without merge still means "drop or re-home"; merged definitely drop
        if [[ "$state" == merged:true ]]; then
          echo "error: PR merged — remove/archive patch listed in $file (PR #${num})" >&2
          fail=1
        fi
      fi
      # strip matched URL and continue if more on line
      line="${line#*pull/${num}}"
    done
  fi
done <"$META"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "check-gamescope-prs: ok"
