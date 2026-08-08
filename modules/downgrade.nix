{
  config,
  lib,
  pkgs,
  ...
}:
let
  mkBin = {
    name,
    url,
    hash,
  }: pkgs.stdenv.mkDerivation {
    inherit name;
    src = pkgs.fetchurl {
      inherit url;
      sha256 = hash;
    };
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/${name}"
      runHook postInstall
    '';
  };

  dgsc = mkBin {
    name = "nix-crab-dgsc";
    url = "https://github.com/Deadboy666/h3adcr-b-modul3s/raw/refs/heads/main/dgsc";
    hash = "sha256-CJUdjpmNl9xKNcuTdsiIuY+l37Pb8D0vyWKZQD/QBCI=";
  };

  dlm = mkBin {
    name = "nix-crab-dlm";
    url = "https://github.com/Deadboy666/h3adcr-b-modul3s/raw/refs/heads/main/dlm";
    hash = "sha256-ly66uMEsDEfvfTn5geCKMzovEfrmlWqzuTZlORecdxQ=";
  };

  sources = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/Deadboy666/h3adcr-b-modul3s/main/sources.txt";
    sha256 = "sha256-Nk4F4fUrEWkfP01Ui7R+O3YERjnwHXy0L8jLDHJkjZA=";
  };

  clientManifest = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/Deadboy666/SteamTracking/refs/heads/headcrab/ClientManifest/steam_client_ubuntu12";
    sha256 = "sha256-jIU3nP16Kk7wLlttO3kXbV+xA5pKIQKo+7FIYfUMQwc=";
  };

  downgrade = pkgs.writeShellScriptBin "nix-crab-downgrade" ''
    set -euo pipefail

    PKG="$HOME/.steam/steam/package"
    STEAMCFG="$HOME/.steam/steam/steam.cfg"
    mkdir -p "$(dirname "$STEAMCFG")" "$PKG"

    if [ ! -f "$STEAMCFG" ]; then
      cat ${./steam.cfg} >"$STEAMCFG"
    fi

    rm -f "$PKG"/*

    cd "$PKG"
    echo "Downloading client manifest..."
    cp ${clientManifest} "$PKG/steam_client_ubuntu12"

    echo "Fetching client files (nix-crab-dlm)..."
    ${dlm}/bin/nix-crab-dlm --input-file ${sources} --max-concurrent 16

    echo "Starting nix-crab-dgsc on :1666..."
    ${dgsc}/bin/nix-crab-dgsc --port 1666 --silent &
    DGSC_PID=$!
    trap 'kill "$DGSC_PID" 2>/dev/null || true' EXIT

    echo "Applying client via Steam override..."
    steam -forcesteamupdate -forcepackagedownload -overridepackageurl http://localhost:1666/ -exitsteam

    echo "Done."
  '';
in {
  options.programs.nix-crab.downgrade = {
    enable = lib.mkEnableOption "nix-crab client downgrade";
    package = lib.mkOption {
      type = lib.types.package;
      default = downgrade;
      description = "The nix-crab-downgrade wrapper script";
    };
  };

  config = lib.mkIf config.programs.nix-crab.downgrade.enable {
    environment.systemPackages = [config.programs.nix-crab.downgrade.package];
  };
}
