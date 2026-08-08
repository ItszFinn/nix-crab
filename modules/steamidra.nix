{
  steamidra,
}: {
  pkgs,
  lib,
  config,
  ...
}: let
  # Newest tag from the pinned /tags JSON (GitHub lists tags newest-first).
  # Re-lock with `nix flake update` to track a new release.
  version = lib.removePrefix "v"
    (builtins.head (builtins.fromJSON (builtins.readFile steamidra))).name;

  # Absolute, not $HOME: this also lands in the .desktop Icon= path, which is
  # not shell-expanded.
  dataDir = "${config.home.homeDirectory}/.local/share/SteaMidra";

  # The release asset URL carries the version, so there is no stable URL that
  # could be a flake input on its own, and fetching the 520 MiB zip from Nix
  # would mean a hand-bumped SRI hash. So the launcher unpacks it into $HOME on
  # first run, for exactly the version the steamidra input is locked to.
  # sff_data_dir() (sff/core/utils.py) writes settings.bin next to the running
  # binary, which is why $HOME (not the store) is the right place anyway.
  steamidraLauncher = pkgs.writeShellScriptBin "steamidra" ''
    set -euo pipefail
    app="${dataDir}/SteaMidra.AppImage"

    if [ "$(cat "${dataDir}/.version" 2>/dev/null || true)" != "${version}" ]; then
      ${pkgs.libnotify}/bin/notify-send -a SteaMidra \
        "Downloading SteaMidra ${version}" "About 520 MiB, this takes a while." || true
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      ${pkgs.curl}/bin/curl -fL --progress-bar -o "$tmp/sff.zip" \
        "https://github.com/Midrags/SFF/releases/download/v${version}/SteaMidra-${version}-linux.zip"
      ${pkgs.unzip}/bin/unzip -qo "$tmp/sff.zip" "SteaMidra*.AppImage" "*.png" -d "$tmp"
      mkdir -p "${dataDir}"
      mv "$tmp"/SteaMidra*.AppImage "$app"
      chmod +x "$app"
      mv "$tmp"/*.png "${dataDir}/steamidra.png"
      echo "${version}" > "${dataDir}/.version"
      ${pkgs.libnotify}/bin/notify-send -a SteaMidra "SteaMidra ${version} ready" || true
    fi

    export APPIMAGE="$app"
    export QTWEBENGINE_DISABLE_SANDBOX=1
    exec ${pkgs.appimage-run}/bin/appimage-run "$app" "$@"
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "steamidra";
    desktopName = "SteaMidra";
    comment = "Steam game setup and manifest tool";
    exec = "${steamidraLauncher}/bin/steamidra";
    # Unpacked from the zip on first run, so missing until then.
    icon = "${dataDir}/steamidra.png";
    categories = ["Utility"];
    startupNotify = false;
  };
in {
  options.programs.nix-crab.steamidra.enable =
    lib.mkEnableOption "SteaMidra (SFF) game downloader";

  config = lib.mkIf config.programs.nix-crab.steamidra.enable {
    home.packages = [
      pkgs.dotnetCorePackages.runtime_9_0
      steamidraLauncher
    ];

    # Not xdg.desktopEntries: that lands in the profile, and SteaMidra writes
    # its own ~/.local/share/applications/steamidra.desktop on startup with
    # Exec pointing at the raw AppImage — which cannot run on NixOS (no
    # libfuse2). XDG_DATA_HOME is searched before the profile, so that broken
    # entry would shadow ours. Own the path and force it back on every switch.
    home.file.".local/share/applications/steamidra.desktop" = {
      source = "${desktopItem}/share/applications/steamidra.desktop";
      force = true;
    };
  };
}
