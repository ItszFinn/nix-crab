{
  sls-steam,
  nix-flatpak,
  steamnetsock,
  cloudredirect-cli,
}: {
  pkgs,
  lib,
  config,
  ...
}: let
  slssteamPkg = sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.sls-steam;

  cloudredirectCli = pkgs.stdenv.mkDerivation {
    pname = "cloud_redirect_cli";
    version = "0.0.0";
    src = cloudredirect-cli;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/cloud_redirect_cli"
      runHook postInstall
    '';
  };

  nixCrabStatus = pkgs.writeShellScriptBin "nix-crab-status" ''
    set -u

    echo "=== Steam Client ==="
    PKG="$HOME/.steam/steam/package"
    VERSION=""
    for f in "$PKG"/steam_client_*; do
      [ -f "$f" ] || continue
      VERSION=$(grep -m1 '"version"' "$f" | awk -F'"' '{print $4}')
      [ -n "$VERSION" ] && break
    done
    if [ -n "$VERSION" ]; then
      echo "Version: $VERSION"
    else
      echo "Version: unknown (no manifest in $PKG)"
    fi

    echo
    echo "=== SLSsteam ==="
    CFG="$HOME/.config/SLSsteam/config.yaml"
    # yaml-cpp lets the LAST duplicate key win, and SteaMidra appends a second
    # flat key block to config.yaml. So always read the last occurrence.
    val() { grep "^$1:" "$CFG" | tail -1 | awk '{print $2}'; }
    if [ -f "$CFG" ]; then
      echo "DisableCloud:   $(val DisableCloud)"
      echo "PlayNotOwned:   $(val PlayNotOwnedGames)"
      echo "SafeMode:       $(val SafeMode)"
      DUPES=$(grep -c '^DisableCloud:' "$CFG")
      [ "$DUPES" -gt 1 ] && echo "Warning:        DisableCloud set $DUPES times - only the last counts"
    else
      echo "Config missing: $CFG"
    fi
    echo "Netsock:        $([ -f "$HOME/.config/SLSsteam/tools/netsock/netsock.so" ] && echo present || echo missing)"

    echo
    echo "=== CloudRedirect ==="
    if [ -f "$CFG" ] && [ "$(val DisableCloud)" = "no" ]; then
      echo "Status: Enabled (DisableCloud: no)"
    else
      echo "Status: Disabled"
    fi
    echo "CLI:            $([ -x "$HOME/.local/share/CloudRedirect/cloud_redirect_lib" ] && echo present || echo missing)"
    echo "Flatpak:        $([ -d "$HOME/.local/share/flatpak/app/org.cloudredirect.CloudRedirect" ] && echo installed || echo not installed)"

    echo
    echo "=== Client-Updates ==="
    if [ -f "$HOME/.steam/steam/steam.cfg" ]; then
      echo "steam.cfg present -> client updates blocked"
    else
      echo "no steam.cfg -> client follows updates"
    fi
  '';
  # The typed sls-steam home module emits booleans as `true`/`false` (remarshal),
  # but headcrab (h3adcr-b.sh) and nix-crab-status grep the literal
  # `DisableCloud: no`. So we reuse the typed option surface but render the file
  # ourselves with YAML 1.1 `yes`/`no` booleans.
  renderVal = v:
    if v == true then "yes"
    else if v == false then "no"
    else if builtins.isList v then
      if v == [] then "[]"
      else "[ " + lib.concatMapStringsSep ", " renderVal v + " ]"
    else if builtins.isAttrs v then
      if v == {} then "{}"
      else
        "{ "
        + lib.concatStringsSep ", "
          (lib.mapAttrsToList (k: val: "${k}: ${renderVal val}") v)
        + " }"
    else if builtins.isString v then "'${v}'"
    else builtins.toString v;

  renderConfig = cfg:
    lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}: ${renderVal v}") cfg)
    + "\n";
in {
  imports = [
    sls-steam.homeModules.sls-steam
    nix-flatpak.homeManagerModules.nix-flatpak
  ];

  options.programs.nix-crab.slssteam.manageConfig = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether Nix should write ~/.config/SLSsteam/config.yaml. Disabled by
      default so tools like SteaMidra can edit the file without it being reset
      on the next home-manager switch. When enabled, the file is generated from
      services.sls-steam.config with headcrab-compatible yes/no booleans.
    '';
  };

  config = {
    # headcrab-compatible defaults: PlayNotOwnedGames yes, DisableCloud no,
    # SafeMode no (SafeMode self-blocks on desktop). mkDefault so user config
    # can override them.
    services.sls-steam.config = {
      PlayNotOwnedGames = lib.mkDefault true;
      DisableCloud = lib.mkDefault false;

      # Keys SLSsteam reads (config.cpp) that the typed module does not declare.
      # Without them SLSsteam notifies "Config loading errors" on every start.
      # Upstream defaults from config_default.hpp:
      MaxSchemaTries = lib.mkDefault 10;
      FakeName = lib.mkDefault "";
      DisableUpdates = lib.mkDefault true;
      DumpClientInterfaces = lib.mkDefault false;
      DepotBlacklist = lib.mkDefault [];
      ManifestIds = lib.mkDefault {};
      SteamIdOverride = lib.mkDefault {};
    };

    # Only manage config.yaml when explicitly enabled. Otherwise neither our
    # renderer nor the typed module writes it, so tools editing the file keep
    # their changes across home-manager switches.
    xdg.configFile."SLSsteam/config.yaml" = {
      enable = config.programs.nix-crab.slssteam.manageConfig;
      # Force the source: the typed module sets `source` as a plain value which
      # would beat the mkDefault source derived from `text`. We render the file
      # ourselves (yes/no booleans, headcrab-compatible).
      source = lib.mkForce (pkgs.writeTextFile {
        name = "SLSsteam-config.yaml";
        text = renderConfig config.services.sls-steam.config;
      });
    };

    services.flatpak = {
      packages = [
        {
          appId = "org.cloudredirect.CloudRedirect";
          origin = "cloudredirect";
        }
      ];
      # The app's SLSsteam check follows ~/.local/share/SLSsteam/SLSsteam.so
      # (see home.file below) into the Nix store, so the sandbox has to see the
      # store — with only filesystems=home that symlink is dangling inside the
      # Flatpak and the check fails.
      overrides.settings."org.cloudredirect.CloudRedirect".Context.filesystems = [
        "/nix/store:ro"
      ];
      remotes = [
        {
          name = "flathub";
          location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
        }
        {
          name = "cloudredirect";
          location = "https://raw.githubusercontent.com/Selectively11/CloudRedirect/refs/heads/gh-pages/cloudredirect.flatpakrepo";
        }
      ];
    };

    home.file = {
      ".config/SLSsteam/tools/netsock/netsock.so".source = steamnetsock;
      # The CloudRedirect app's prerequisite check stats
      # $XDG_DATA_HOME/SLSsteam/SLSsteam.so (the imperative h3adcr-b layout).
      # Nix keeps SLSsteam in the store, so without this link the app shows
      # "SLSsteam: Not found" and refuses to deploy/update.
      ".local/share/SLSsteam/SLSsteam.so".source = "${slssteamPkg}/SLSsteam.so";
      ".local/share/CloudRedirect/cloud_redirect_lib".source =
        "${cloudredirectCli}/bin/cloud_redirect_cli";
    };

    home.packages = [cloudredirectCli nixCrabStatus];
  };
}
