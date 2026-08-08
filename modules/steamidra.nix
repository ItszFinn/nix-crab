{
  steamidra,
}: {
  pkgs,
  lib,
  config,
  ...
}: let
  # GitHub API releases/latest — re-lock with `nix flake update` to track the
  # newest release. Version and asset URL are derived from this JSON.
  meta = builtins.fromJSON (builtins.readFile steamidra);

  version = lib.removePrefix "v" meta.tag_name;

  linuxZip = builtins.head (
    builtins.filter (a: lib.hasSuffix "-linux.zip" a.name) meta.assets
  );

  zip = pkgs.fetchurl {
    url = linuxZip.browser_download_url;
    # Bump this SRI hash when a new release ships (same rule as downgrade.nix).
    sha256 = "sha256-LICtDm4Lwstw2vKpBy5XAeXgdlMRV/dXkmnlqZw06Xg=";
  };

  steamidraAssets = pkgs.runCommand "steamidra-assets" {
    nativeBuildInputs = [pkgs.unzip];
  } ''
    mkdir -p $out
    unzip -q ${zip} "SteaMidra*.AppImage" -d $out
    unzip -q ${zip} "*.png" -d $out
    mv $out/SteaMidra*.AppImage $out/SteaMidra.AppImage
    mv $out/*.png $out/steamidra.png
  '';

  steamidraWrapped = pkgs.appimageTools.wrapType2 {
    pname = "steamidra";
    inherit version;
    src = "${steamidraAssets}/SteaMidra.AppImage";
  };

  # sff_data_dir() (sff/core/utils.py) writes settings.bin next to the running
  # binary. wrapType2 puts the binary in the read-only Nix store, so we point
  # APPIMAGE at a writable $HOME path (same location as the official installer)
  # to make root_folder() resolve there.
  steamidraLauncher = pkgs.writeShellScriptBin "steamidra" ''
    export APPIMAGE="$HOME/.local/share/SteaMidra/SteaMidra.AppImage"
    mkdir -p "$(dirname "$APPIMAGE")"
    export QTWEBENGINE_DISABLE_SANDBOX=1
    exec ${steamidraWrapped}/bin/steamidra "$@"
  '';
in {
  options.programs.nix-crab.steamidra.enable =
    lib.mkEnableOption "SteaMidra (SFF) game downloader";

  config = lib.mkIf config.programs.nix-crab.steamidra.enable {
    home.packages = [
      pkgs.dotnetCorePackages.runtime_9_0
      steamidraLauncher
    ];

    home.file.".local/share/icons/hicolor/256x256/apps/steamidra.png".source =
      "${steamidraAssets}/steamidra.png";

    xdg.desktopEntries.steamidra = {
      name = "SteaMidra";
      comment = "Steam game setup and manifest tool";
      exec = "${steamidraLauncher}/bin/steamidra";
      icon = "${steamidraAssets}/steamidra.png";
      terminal = false;
      categories = ["Utility"];
      startupNotify = false;
    };
  };
}
