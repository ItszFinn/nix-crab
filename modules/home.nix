{
  sls-steam,
  nix-flatpak,
  steamnetsock,
  cloudredirect,
  cloudredirect-moon,
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
    echo "=== Games (slsteam-moon / LuaTools) ==="
    # slsteam-moon does NOT write added games into config.yaml's AdditionalApps
    # (that section is deprecated). Games are <appid>.lua files in Steam's
    # stplug-in dir, plus manual appids in luaappids.yaml.
    STPLUG=""
    for root in "$HOME/.steam/steam" "$HOME/.steam/debian-installation" "$HOME/.local/share/Steam"; do
      if [ -d "$root/config/stplug-in" ]; then STPLUG="$root/config/stplug-in"; break; fi
    done
    if [ -n "$STPLUG" ]; then
      COUNT=$(find "$STPLUG" -maxdepth 1 -name '*.lua' 2>/dev/null | wc -l | tr -d ' ')
      echo "stplug-in:      $COUNT lua manifests ($STPLUG)"
    else
      echo "stplug-in:      missing (no Steam root with config/stplug-in)"
    fi
    if [ -f "$HOME/.config/SLSsteam/luaappids.yaml" ]; then
      echo "luaappids.yaml: present (manual AdditionalApps list)"
    else
      echo "luaappids.yaml: none"
    fi

    echo
    echo "=== CloudRedirect ==="
    # Both spellings: SLSsteam and SteaMidra write YAML 1.2 true/false, a
    # hand-edited or headcrab-era config carries YAML 1.1 yes/no.
    case "$([ -f "$CFG" ] && val DisableCloud)" in
      no | false) echo "Status: Enabled (DisableCloud: $(val DisableCloud))" ;;
      *)          echo "Status: Disabled" ;;
    esac
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
      services.sls-steam.config by the upstream sls-steam module.
    '';
  };

  options.programs.nix-crab.cloudredirect.moon.enable = lib.mkEnableOption ''
    the cloudredirect-moon hook instead of upstream CloudRedirect for the
    ~/.local/share/CloudRedirect/cloud_redirect.so link. Must match the NixOS
    module's programs.nix-crab.cloudredirect.moon.enable. Only enable for the
    LuaTools stack.
  '';

  config = {
    # headcrab-equivalent defaults: PlayNotOwnedGames on, DisableCloud off,
    # SafeMode off (SafeMode self-blocks on desktop). mkDefault so user config
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

      # Upstream's C++ renamed LogLevel -> LogLevels (bitwise flags, 0xff = all
      # levels) and added CDKeys, but its own typed module still declares only
      # the old LogLevel enum -- so both keys are missing from the generated
      # file and SLSsteam reports "Missing LogLevels" / "Missing CDKeys" on
      # every start. Drop these two once the typed module catches up.
      LogLevels = lib.mkDefault 255;
      CDKeys = lib.mkDefault {};
    };

    # Only manage config.yaml when explicitly enabled. Otherwise the typed
    # module's source is still evaluated but never written, so tools editing the
    # file keep their changes across home-manager switches.
    xdg.configFile."SLSsteam/config.yaml".enable =
      config.programs.nix-crab.slssteam.manageConfig;

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
      # Same deal for CloudRedirect's own deploy check: it stats
      # $XDG_DATA_HOME/CloudRedirect/cloud_redirect.so and reports "failed to
      # deploy" without it. Follow the same hook choice as the LD_PRELOAD in
      # modules/cloudredirect.nix so the app's status matches what is injected.
      ".local/share/CloudRedirect/cloud_redirect.so".source =
        if config.programs.nix-crab.cloudredirect.moon.enable
        then "${cloudredirect-moon}/cloud_redirect.so"
        else cloudredirect;
    };

    home.packages = [cloudredirectCli nixCrabStatus];
  };
}
