{
  lumen,
  luatools-moon,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.nix-crab.luatools;

  lumenDir = "${config.xdg.dataHome}/Lumen";
  stampDir = "${lumenDir}/.nix-crab";

  # Build the two dists into store paths. The activation below copies them
  # into real directories because Lumen and the plugin write at runtime
  # (config, fetched manifest packs, plugin state).
  lumenDist = pkgs.runCommand "lumen-dist" {} ''
    mkdir -p "$out"
    ${pkgs.unzip}/bin/unzip -qo ${lumen}/dist/lumen-linux.zip -d "$out"
    chmod +x "$out/lumen"
  '';

  # The plugin ships no committed dist zip, only the canonical plugin/ source
  # tree. Package it the same way upstream's scripts/build.sh does, but
  # deterministically (SKIP_INDEX_REFRESH: keep the committed ryuu_index.json).
  luatoolsDist = pkgs.runCommand "luatools-moon-dist" {} ''
    mkdir -p "$out"
    cp -r ${luatools-moon}/plugin/. "$out/"
    rm -rf "$out/backend/data" "$out/backend/temp_dl"
    rm -f "$out/backend/lua_runtime.log" "$out/backend/loadedappids.txt" "$out/backend/appidlogs.txt"
    chmod +x "$out/backend/scripts/"*.sh "$out/backend/bin/7zz"
  '';
in {
  options.programs.nix-crab.luatools.enable = lib.mkEnableOption ''
    the LuaTools stack for slsteam-moon: Lumen (backend) and the LuaTools
    plugin, placed under ~/.local/share/Lumen. Requires
    programs.nix-crab.slssteam-moon.enable on the NixOS side (that also brings
    steam-run, which the `lumen` wrapper needs).
  '';

  config = lib.mkIf cfg.enable {
    home.packages = [
      # Convenience entry point for attaching to an already-running Steam. The
      # activation-written ~/.local/share/Lumen/lumen shim is the single place
      # that knows how to start Lumen (steam-run sandbox, backend dir, loader
      # env); this only puts it on PATH.
      (pkgs.writeShellScriptBin "lumen" ''
        exec "$HOME/.local/share/Lumen/lumen" "$@"
      '')

      # Shadow the system `steam` so that launching Steam -- via the `steam`
      # command or its desktop entry -- also brings up Lumen. This only exists
      # while luatools.enable is set, so it is exactly the "when Lumen is used"
      # behaviour.
      (pkgs.writeShellScriptBin "steam" ''
        # The real Steam launcher is the first `steam` on PATH that is not this
        # very wrapper (our own profile dir shadows the system one). -ef skips
        # symlinks to ourselves too.
        real_steam=""
        oIFS=$IFS
        IFS=:
        for d in $PATH; do
          [ -n "$d" ] || continue
          cand="$d/steam"
          [ -x "$cand" ] || continue
          [ "$cand" -ef "$0" ] && continue
          real_steam="$cand"
          break
        done
        IFS=$oIFS
        if [ -z "$real_steam" ]; then
          echo "nix-crab: system Steam launcher not found on PATH" >&2
          exit 1
        fi

        # Start Lumen detached, mirroring slsteam-moon's own generated launcher
        # (setup.sh): pgrep-guarded, because nothing in Lumen is single-instance
        # and a second `steam` invocation -- a steam:// link from the browser, a
        # second desktop-entry click -- would stack another sidecar on the same
        # CEF target. No waiting for cef_port either: Lumen polls for it itself
        # (lua/cefport.lua), so there is nothing to synchronise here.
        #
        # The loader env is dropped inside the steam-run sandbox, not here --
        # see the shim in the activation below for why.
        LUMEN_DIR="$HOME/.local/share/Lumen"
        if [ -x "$LUMEN_DIR/lumen" ] \
          && ! ${pkgs.procps}/bin/pgrep -f "$LUMEN_DIR/lumen" >/dev/null 2>&1; then
          ${pkgs.util-linux}/bin/setsid "$LUMEN_DIR/lumen" >/dev/null 2>&1 </dev/null &
        fi

        exec "$real_steam" "$@"
      '')
    ];

    # Steam only exposes its CEF remote-debugging endpoint (which Lumen
    # injects through) when the .cef-enable-remote-debugging marker exists;
    # otherwise the webhelper starts with no debug port and slsteam-moon has
    # nothing to rewrite (no ~/.local/share/Lumen/cef_port, Lumen cannot
    # attach). Upstream's slsteam-moon launcher wrapper touches this on every
    # Steam start; replicate that declaratively. Best-effort: only the roots
    # that exist on this system. A Steam restart is needed after creating it.
    home.activation.luatoolsCefMarker = lib.hm.dag.entryAfter ["writeBoundary"] ''
      touch "$HOME/.steam/steam/.cef-enable-remote-debugging" 2>/dev/null || true
      touch "$HOME/.steam/debian-installation/.cef-enable-remote-debugging" 2>/dev/null || true
    '';

    home.activation.luatoolsMoon = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Re-sync only when the pinned input changes (nix flake update) or $4
      # forces it. Kept separate from crabInstall so the install itself runs as
      # a plain statement: a function called in an `if` condition has errexit
      # disabled, and a failed copy would then be reported as "up to date".
      crabNeedsSync() {
        src=$1 dir=$2 stamp=$3 force=''${4:-0}
        [ "$force" = 0 ] && [ -f "$stamp" ] \
          && [ "$(cat "$stamp")" = "$src" ] && [ -d "$dir" ] && return 1
        return 0
      }

      # Copy a store dist into a writable dir. Removes just the files the
      # PREVIOUS dist installed -- the stamp holds its store path -- so the
      # state these dists deliberately exclude survives an input bump:
      # cef_port, notifications/, ryuu_index.json, luatools/ under Lumen, and
      # backend/data, backend/temp_dl, the logs under the plugin.
      crabInstall() {
        src=$1 dir=$2 stamp=$3
        # A leftover copy from the store (or a failed install) is read-only
        # (555) and would block the removal and the overwrite below; make it
        # writable first. chmod works on files you own even when they are not.
        run chmod -R u+w "$dir" 2>/dev/null || true
        if [ -f "$stamp" ] && old=$(cat "$stamp") && [ -d "$old" ]; then
          (cd "$old" && find . ! -type d) | while read -r f; do
            run rm -f "$dir/$f"
          done
        fi
        run mkdir -p "$dir"
        run cp -r "$src"/. "$dir"/
        run chmod -R u+w "$dir"
      }

      # The stamp is written last, so an install that dies halfway is retried
      # on the next switch instead of being recorded as current.
      crabStamp() {
        run mkdir -p "${stampDir}"
        tmp=$(mktemp)
        printf '%s' "$1" > "$tmp"
        run install -m644 "$tmp" "$2"
        rm -f "$tmp"
      }

      src="${lumenDist}"
      dir="${lumenDir}"
      stamp="${stampDir}/lumen-src"

      # The steam-run shim is written here rather than shipped in the dist, so a
      # dir that lost it -- or predates the current shim -- has to be rebuilt
      # even when the stamp still matches.
      force=0
      if [ ! -x "$dir/lumen" ] || ! grep -q 'env -u LD_AUDIT' "$dir/lumen" 2>/dev/null; then
        force=1
      fi

      if crabNeedsSync "$src" "$dir" "$stamp" "$force"; then
        crabInstall "$src" "$dir" "$stamp"
        # Lumen's prebuilt ELF needs an FHS sandbox on NixOS. The upstream
        # installer renames the raw binary and drops a steam-run wrapper in its
        # place (install.sh, NixOS branch); do the same here. lumen.bin resolves
        # lua/ relative to its working directory, so the wrapper cd's into the
        # install dir first. LUMEN_BACKEND_DIR is how Lumen discovers the
        # LuaTools plugin backend (boot.lua only loads it when the variable is
        # set); without it every plugin call fails with "unknown method".
        #
        # The LD_AUDIT/LD_PRELOAD unset has to happen INSIDE steam-run: those
        # carry slsteam-moon's 32-bit hooks, and pkgs.steam's extraEnv lands in
        # the FHS rootfs /etc/profile, which steam-run sources -- so unsetting
        # them outside is a no-op and 64-bit Lumen plus every backend script it
        # spawns gets a round of "wrong ELF class" from ld.so. LD_LIBRARY_PATH
        # stays: inside the sandbox it is what makes the FHS libs resolvable.
        #
        # Do NOT run alejandra on this file: it re-indents the heredoc body and
        # its terminator, and <<'EOF' only ends on an EOF in column 0, so the
        # shim would swallow the rest of the activation. Breaks at switch time,
        # not at eval time.
        run rm -f "$dir/lumen.bin"
        run mv "$dir/lumen" "$dir/lumen.bin"
        cat > "$dir/lumen" <<'EOF'
#!/bin/sh
cd "$(dirname "$0")" || exit 1
export LUMEN_BACKEND_DIR="$PWD/luatools/backend"
export LUMEN_LUA_DIR="$PWD/lua"
exec steam-run env -u LD_AUDIT -u LD_PRELOAD ./lumen.bin "$@"
EOF
        run chmod +x "$dir/lumen"
        crabStamp "$src" "$stamp"
        echo "nix-crab: installed LuaTools (Lumen) to $dir"
      else
        echo "nix-crab: LuaTools (Lumen) is up to date"
      fi

      # The plugin lives under Lumen's own luatools/ dir.
      psrc="${luatoolsDist}"
      pdir="${lumenDir}/luatools"
      pstamp="${stampDir}/luatools-src"
      if crabNeedsSync "$psrc" "$pdir" "$pstamp"; then
        crabInstall "$psrc" "$pdir" "$pstamp"
        crabStamp "$psrc" "$pstamp"
        echo "nix-crab: installed LuaTools plugin to $pdir"
      else
        echo "nix-crab: LuaTools plugin is up to date"
      fi
    '';
  };
}
