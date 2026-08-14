{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.nix-crab.millennium;

  # The two live apart on Linux: plugins follow MILLENNIUM__PLUGINS_PATH from
  # Millennium's environment map (XDG data home), themes follow its internal
  # get_millennium_path(), which is the Steam directory. Our own bookkeeping
  # stays next to the plugins.
  pluginsDir = "${config.xdg.dataHome}/millennium/plugins";
  themesDir = "${config.home.homeDirectory}/.steam/steam/millennium/themes";
  stampDir = "${config.xdg.dataHome}/millennium/.nix-crab";

  # An empty ID would make the store lookup match the first entry in the index
  # (`startswith("")` is true for everything) and install a random addon.
  ids = list:
    lib.warnIf (lib.elem "" list) "nix-crab: ignoring an empty ID in programs.nix-crab.millennium"
    (lib.filter (id: id != "") list);
in {
  options.programs.nix-crab.millennium = {
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["3dc714a7c1b1"];
      description = ''
        Millennium plugin IDs from https://steambrew.app/plugins -- the `id` in
        a plugin's store URL (https://steambrew.app/plugin/<id>). Each one is
        unpacked into ~/.local/share/millennium/plugins on activation unless it
        is already installed.
      '';
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["1wwKwvHrFuzMs7Kb1Uzu" "Adwaita"];
      description = ''
        Millennium theme IDs from https://steambrew.app/themes -- the `id` in a
        theme's store URL (https://steambrew.app/theme/<id>), or the theme's
        display name or GitHub repo name, whichever is at hand. Each one is
        unpacked into ~/.steam/steam/millennium/themes on activation
        unless it is already installed. Pick the active theme in Millennium's UI
        afterwards.
      '';
    };
  };

  # Not gated on the lists being non-empty: emptying them has to still run, or
  # removing the last ID would leave the addon installed forever.
  config = {
    # Downloaded at activation instead of fetchzip: both stores serve the
    # newest commit of an addon, so a pinned hash would break on every upstream
    # release. Same trade-off as steamidra. Real directories, not store
    # symlinks -- Millennium writes into these folders (settings, its own
    # updater) and cannot write into /nix/store.
    home.activation.millenniumAddons = lib.hm.dag.entryAfter ["writeBoundary"] ''
      export PATH="${lib.makeBinPath [pkgs.curl pkgs.jq pkgs.unzip]}:$PATH"

      stampDir="${stampDir}"

      # kind, target dir, index API, jq program resolving an ID to
      # "<zip url>|<folder>|<metadata.json>", then the configured IDs.
      crabSync() {
        kind=$1 dir=$2 api=$3 prog=$4
        shift 4

        # The stamp file holds the folder name, so removal only ever deletes
        # what this module installed.
        for stamp in "$stampDir/$kind-"*; do
          [ -e "$stamp" ] || continue
          id=$(basename "$stamp"); id=''${id#"$kind-"}
          for want in "$@"; do [ "$want" = "$id" ] && continue 2; done
          folder=$(cat "$stamp")
          if [ -n "$folder" ]; then run rm -rf "$dir/$folder"; fi
          run rm -f "$stamp"
          echo "nix-crab: removed $kind '$id'"
        done

        index=""
        for id in "$@"; do
          # Stamp alone is not enough: if the folder it names is gone (deleted
          # by hand, or left behind by an older layout), install it again.
          stampFile="$stampDir/$kind-$id"
          if [ -e "$stampFile" ] && [ -d "$dir/$(cat "$stampFile")" ]; then continue; fi
          if [ -z "$index" ] && ! index=$(curl -fsS "$api"); then
            echo "nix-crab: $kind store unreachable" >&2
            return 0
          fi

          entry=$(printf '%s' "$index" | jq -r --arg id "$id" "$prog")
          if [ -z "$entry" ] || [ "$entry" = "null" ]; then
            echo "nix-crab: no Millennium $kind '$id' in the store" >&2
            continue
          fi
          IFS='|' read -r url folder meta <<< "$entry"

          tmp=$(mktemp -d)
          # Every archive here holds a single top-level folder, so the glob
          # resolves to one path -- and mv fails loudly if it ever does not.
          if curl -fsSL -o "$tmp/a.zip" "$url" && unzip -qo "$tmp/a.zip" -d "$tmp/x"; then
            run mkdir -p "$dir" "$stampDir"
            run rm -rf "$dir/$folder"
            run mv "$tmp"/x/* "$dir/$folder"
            printf '%s' "$meta" > "$tmp/metadata.json"
            printf '%s' "$folder" > "$tmp/stamp"
            [ -n "$meta" ] && run install -m644 "$tmp/metadata.json" "$dir/$folder/metadata.json"
            run install -m644 "$tmp/stamp" "$stampDir/$kind-$id"
            echo "nix-crab: installed $kind '$folder'"
          else
            echo "nix-crab: install failed for $kind '$id'" >&2
          fi
          rm -rf "$tmp"
        done
      }

      # The store URL carries the first 12 chars of initCommitId, the download
      # endpoint wants all 40 -- startswith accepts either spelling.
      crabSync plugin "${pluginsDir}" https://steambrew.app/api/v1/plugins '
        first(.[] | select(.initCommitId | startswith($id)))
        | "https://steambrew.app/api/v1/plugins/download?id=\(.initCommitId)&n=\(.pluginJson.name)|\(.pluginJson.name)|"
      ' ${lib.escapeShellArgs (ids cfg.plugins)}

      # Themes have no single canonical handle: take ID, display name or repo.
      # The metadata.json is what Millennium writes after its own install; its
      # updater needs it to tell which commit is on disk.
      crabSync theme "${themesDir}" https://steambrew.app/api/v2 '
        first(.[] | select(.data.id == $id or .name == $id or .data.github.repo == $id))
        | "\(.download)|\(.data.github.repo)|"
          + ({owner: .data.github.owner, repo: .data.github.repo, commit: .commit_data.oid} | tojson)
      ' ${lib.escapeShellArgs (ids cfg.themes)}
    '';
  };
}
