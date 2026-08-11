#!/usr/bin/env bash
# Clone ponytail + mattpocock/skills into .agents/vendor and link into .agents/skills.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/.agents/vendor"
SKILLS="$ROOT/.agents/skills"

mkdir -p "$VENDOR" "$SKILLS"

clone_or_update() {
  local url="$1" dir="$2"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --ff-only || true
  else
    git clone --depth 1 "$url" "$dir"
  fi
}

clone_or_update https://github.com/DietrichGebert/ponytail.git "$VENDOR/ponytail"
clone_or_update https://github.com/mattpocock/skills.git "$VENDOR/mattpocock-skills"

# Refresh skill symlinks
find "$SKILLS" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
for d in "$VENDOR/ponytail/skills"/*/; do
  name="$(basename "$d")"
  ln -sfn "../vendor/ponytail/skills/$name" "$SKILLS/$name"
done
for d in "$VENDOR/mattpocock-skills/skills/engineering"/*/; do
  name="$(basename "$d")"
  ln -sfn "../vendor/mattpocock-skills/skills/engineering/$name" "$SKILLS/$name"
done
for name in grill-me handoff wait-what; do
  if [[ -d "$VENDOR/mattpocock-skills/skills/productivity/$name" ]]; then
    ln -sfn "../vendor/mattpocock-skills/skills/productivity/$name" "$SKILLS/$name"
  fi
done

echo "setup-skills: linked $(find "$SKILLS" -mindepth 1 -maxdepth 1 | wc -l) skills"
