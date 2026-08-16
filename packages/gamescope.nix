# `punktfunk-gamescope` — ValveSoftware/gamescope **master** plus unom's full
# `pipewire-hdr` series, exposed under its own name so it sits BESIDE the system
# gamescope instead of replacing it.
#
# Tracks master (not only the nixpkgs tag), same stance as polaris/gamescope-polaris:
# #2271 (bSampled + XBGR RGB10 fallback) is already on main — we do NOT vendor it.
# Functional patches come from unom (`punktfunk-src/packaging/gamescope/patches`);
# `gamescope-patches/` is overlay extras only. WSI layer is built with the compositor
# and re-homed under $out/lib/punktfunk so the NixOS module can set
# PUNKTFUNK_GAMESCOPE_WSI_LAYER_DIR.
#
# An override rather than a from-scratch derivation on purpose: gamescope vendors
# wlroots, vkroots, libliftoff, … as git submodules; nixpkgs already solves the
# native deps / wrapProgram / gamescopereaper bake. We replace `src` with a pinned
# master tip, filter nixpkgs patches that still apply, add ours, and vendor glm/stb
# wrap-git deps so the sandbox stays offline.
#
# Bump Valve pin: update `gamescopeRev` + `src.hash` (and glm/stb only if wraps
# move), then `scripts/update-gamescope.sh --check`. Unom series rides
# `punktfunk-src`; extras live in `gamescope-patches/`.
{
  lib,
  gamescope,
  fetchFromGitHub,
  python3,
  patchDirs,
  manifestRewriter,
}:
let
  # Master tip 2026-08-11 — includes ValveSoftware/gamescope#2271.
  gamescopeRev = "9ab4ace0083232e66a9922d78880890e71607001";

  # Master switched glm/stb from system headers to meson wrap-git subprojects.
  # Vendoring keeps wrap_mode=nodownload happy in the nix sandbox.
  glmSrc = fetchFromGitHub {
    owner = "g-truc";
    repo = "glm";
    rev = "0af55ccecd98d4e5a8d1fad7de25ba429d60e863";
    hash = "sha256-GnGyzNRpzuguc3yYbEFtYLvG+KiCtRAktiN+NvbOICE=";
  };
  stbSrc = fetchFromGitHub {
    owner = "nothings";
    repo = "stb";
    rev = "5736b15f7ea0ffb08dd38af21067c314d6a3aae9";
    hash = "sha256-s2ASdlT3bBNrqvwfhhN6skjbmyEnUgvNOrvhgUSRj98=";
  };

  # As of nixos-unstable (checked 2026-07-28) `gamescope` IS the buildable
  # derivation. Revisions that wrap it expose the build as `.unwrapped`.
  base = gamescope.unwrapped or gamescope;
  unwrapped =
    if base ? src then
      base
    else
      throw ''
        punktfunk-gamescope needs a buildable gamescope derivation (one with a `src` that
        `overrideAttrs` can patch); this nixpkgs' `gamescope` is neither that nor a wrapper
        exposing `.unwrapped`. Update nixpkgs, or build the compositor with
        packaging/gamescope/build-punktfunk-gamescope.sh instead.
      '';
in
unwrapped.overrideAttrs (old: {
  pname = "punktfunk-gamescope";
  version = "0-unstable-2026-08-11";

  src = fetchFromGitHub {
    owner = "ValveSoftware";
    repo = "gamescope";
    rev = gamescopeRev;
    fetchSubmodules = true;
    hash = "sha256-JaJpGX4GOupMQ9drsqO2aMfLWLqn7SOtEPEtZkd9neA=";
  };

  # Keep only nixpkgs packaging patches that still apply on master.
  # Pending upstream fetchpatches on 3.16.x are already in this tip.
  # Then unom's series, then overlay extras — each dir in lexicographic 000N- order.
  patches =
    (builtins.filter (
      p:
      let
        s = toString p;
      in
      lib.hasInfix "shaders-path" s || lib.hasInfix "gamescopereaper" s
    ) (old.patches or [ ]))
    ++ lib.concatMap (
      dir:
      map (f: "${dir}/${f}") (
        builtins.filter (lib.hasSuffix ".patch") (builtins.attrNames (builtins.readDir dir))
      )
    ) patchDirs;

  # Master dropped glm_include_dir / stb_include_dir meson options.
  mesonFlags = [
    (lib.mesonBool "enable_gamescope" true)
    (lib.mesonBool "enable_gamescope_wsi_layer" true)
    (lib.mesonBool "enable_tests" false)
  ];

  # Materialize glm/stb wrap-git deps from nix store, then stamp a real version
  # into meson (no `.git` on the fetchFromGitHub src).
  postPatch = (old.postPatch or "") + ''
    rm -rf subprojects/glm subprojects/stb
    cp -a ${glmSrc} subprojects/glm
    cp -a ${stbSrc} subprojects/stb
    chmod -R u+w subprojects/glm subprojects/stb
    cp -f subprojects/packagefiles/glm/meson.build subprojects/glm/meson.build
    cp -f subprojects/packagefiles/stb/meson.build subprojects/stb/meson.build

    substituteInPlace src/meson.build \
      --replace-fail \
        "vcs_tag = run_command(vcs_tag_cmd, check: false).stdout().strip()" \
        "vcs_tag = '${gamescopeRev}'"
  '';

  # Expose the compositor under our own name, ADDITIVELY — a symlink beside
  # nixpkgs' own layout rather than a rename plus a sweep of everything else.
  # (See git history: sweeping breaks wrapProgram / gamescopereaper / ReShade.)
  #
  # Also ship the WSI layer we built beside this compositor, rewritten to a
  # distinct name/path/enable var so it sits next to the system FROG layer.
  # A game nested here gets its HDR10 swapchain from this layer or from nowhere;
  # a layer built for a different gamescope makes the compositor reject
  # swapchain_feedback. unom 0.28.1's module points
  # PUNKTFUNK_GAMESCOPE_WSI_LAYER_DIR at $out/lib/punktfunk/vulkan/implicit_layer.d.
  postInstall = (old.postInstall or "") + ''
    ln -s gamescope $out/bin/punktfunk-gamescope

    layerSo=$(find $out -type f -name 'libVkLayer_*gamescope_wsi*.so' | head -1)
    layerJson=$(find $out -type f -name '*gamescope_wsi*.json' | head -1)
    if [ -z "$layerSo" ] || [ -z "$layerJson" ]; then
      echo "punktfunk-gamescope: this gamescope built no WSI layer, so no game under the" >&2
      echo "                     compositor could ever obtain an HDR10 swapchain" >&2
      exit 1
    fi
    ${python3}/bin/python3 ${manifestRewriter} \
      "$layerJson" "$TMPDIR/pf-layer.json" \
      "$out/lib/punktfunk/libVkLayer_PUNKTFUNK_gamescope_wsi.so"
    install -Dm0755 "$layerSo" \
      "$out/lib/punktfunk/libVkLayer_PUNKTFUNK_gamescope_wsi.so"
    install -Dm0644 "$TMPDIR/pf-layer.json" \
      "$out/lib/punktfunk/vulkan/implicit_layer.d/punktfunk_gamescope_wsi.json"
  '';

  # `gamescope --version` exits non-zero on some builds; the grep is the real assertion.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/punktfunk-gamescope --version 2>&1 | grep -q '+pfhdr' \
      || { echo "punktfunk-gamescope: the +pfhdr marker is missing — the patches did not take"; exit 1; }
    lib=$(sed -n 's/.*"library_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      $out/lib/punktfunk/vulkan/implicit_layer.d/punktfunk_gamescope_wsi.json)
    [ -f "$lib" ] \
      || { echo "punktfunk-gamescope: the layer manifest points at $lib, which is not installed"; exit 1; }
    runHook postInstallCheck
  '';

  meta = (old.meta or { }) // {
    description = "gamescope master (${lib.substring 0 7 gamescopeRev}) with 10-bit BT.2020/PQ PipeWire capture (+ #2271 in-tree), for punktfunk HDR streaming";
    mainProgram = "punktfunk-gamescope";
  };
})
