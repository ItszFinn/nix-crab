{
  accela,
}: {
  pkgs,
  lib,
  config,
  ...
}: let
  # deps.tar.gz layout is fixed by ACCELAINSTALL's appimage branch.
  dist = pkgs.runCommand "accela-dist" {} ''
    mkdir -p $out
    tar -xzf ${accela} --strip-components=1 -C $out \
      bin/ACCELA.AppImage bin/accela.png
    chmod +x $out/ACCELA.AppImage
  '';

  # appimage-run also supplies the FHS loader the bundled DepotDownloaderMod
  # needs. zstd is not in that rootfs and the bundled PyQt6 links it, so without
  # the override it dies on `import PyQt6.QtGui` -- eval and build pass either
  # way, only launching catches it.
  # ponytail: just the one lib this bundle needs; a later ImportError names the next.
  appimageRun = pkgs.appimage-run.override {
    extraPkgs = p: [p.zstd];
  };

  launcher = pkgs.writeShellScriptBin "accela" ''
    exec ${appimageRun}/bin/appimage-run ${dist}/ACCELA.AppImage "$@"
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "accela";
    desktopName = "ACCELA";
    comment = "ＧｏＤ_Ｉｓ_ｉＮ_ｔＨｅ_ＷｉＲｅＤ";
    exec = "${launcher}/bin/accela %u";
    icon = "accela";
    categories = ["Utility"];
    # Declared, not registered as default: that would mean owning
    # ~/.config/mimeapps.list via xdg.mimeApps and every other default with it.
    mimeTypes = ["x-scheme-handler/accela"];
    startupNotify = false;
  };

  # The [General] keys enter-the-wired's own `accela` script forces -- what makes
  # ACCELA defer to SLSsteam instead of managing games itself.
  seedConf = pkgs.writeText "ACCELA.conf" ''
    [General]
    auto_skip_single_choice=true
    library_mode=true
    max_downloads=16
    sls_config_management=true
    slssteam_mode=true
    use_steamless=true
  '';
in {
  options.programs.nix-crab.accela.enable =
    lib.mkEnableOption "ACCELA (Steam depot downloader, Enter The Wired)";

  config = lib.mkIf config.programs.nix-crab.accela.enable {
    home.packages = [launcher];

    home.file.".local/share/icons/hicolor/256x256/apps/accela.png".source = "${dist}/accela.png";

    # Not xdg.desktopEntries: XDG_DATA_HOME is searched before the profile, so
    # the entry ACCELAINSTALL writes would shadow ours. Same as steamidra.
    home.file.".local/share/applications/accela.desktop" = {
      source = "${desktopItem}/share/applications/accela.desktop";
      force = true;
    };

    # Seeded, not managed: QSettings rewrites this file, so a store symlink
    # breaks it. Same reason slssteam.manageConfig defaults to false.
    # ponytail: seeds only when absent; upstream awk-merges into an existing section.
    home.activation.accelaSeedConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      accelaConf="${config.xdg.configHome}/Tachibana Labs/ACCELA.conf"
      if [ ! -e "$accelaConf" ]; then
        run mkdir -p "$(dirname "$accelaConf")"
        run install -m 644 ${seedConf} "$accelaConf"
      fi
    '';
  };
}
