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

    MODE="text"
    if [ $# -ge 1 ] && [ "$1" = "--json" ]; then
      MODE="json"
    fi

    PKG="$HOME/.steam/steam/package"
    CFG="$HOME/.config/SLSsteam/config.yaml"
    NETSOOK="$HOME/.config/SLSsteam/tools/netsock/netsock.so"
    STEAMCFG="$HOME/.steam/steam/steam.cfg"
    LUMEN_DIR="$HOME/.local/share/Lumen"
    CRLINK="$HOME/.local/share/CloudRedirect/cloud_redirect.so"

    # Both CloudRedirect hooks are store paths known at Nix build time.
    # Resolve the ~/.local/share link against them to report which one is
    # actually wired up (the home link mirrors the LD_PRELOAD choice).
    # Upstream is a `type = "file"` input (the .so itself); moon is a git
    # input with the .so at the repo root.
    CR_UP="${cloudredirect}"
    CR_MOON="${cloudredirect-moon}/cloud_redirect.so"
    # flat key block to config.yaml. So always read the last occurrence.
    val() { grep "^$1:" "$CFG" | tail -1 | awk '{print $2}'; }

    json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    json_str()   { printf '"%s"' "$(json_escape "$1")"; }
    json_bool()  { [ "$1" = 1 ] && printf 'true' || printf 'false'; }

    # -- Steam client -------------------------------------------------------
    STEAM_VERSION=""
    STEAM_NOTE=""
    for f in "$PKG"/steam_client_*; do
      [ -f "$f" ] || continue
      STEAM_VERSION=$(grep -m1 '"version"' "$f" | awk -F'"' '{print $4}')
      [ -n "$STEAM_VERSION" ] && break
    done
    if [ -z "$STEAM_VERSION" ]; then
      STEAM_VERSION="unknown"
      STEAM_NOTE="no manifest in $PKG"
    fi

    # -- SLSsteam config ----------------------------------------------------
    CONFIG_PRESENT=0
    [ -f "$CFG" ] && CONFIG_PRESENT=1
    DISABLECLOUD=""
    PLAYNOTOWNED=""
    SAFEMODE=""
    DUPES=0
    if [ "$CONFIG_PRESENT" = 1 ]; then
      DISABLECLOUD="$(val DisableCloud)"
      PLAYNOTOWNED="$(val PlayNotOwnedGames)"
      SAFEMODE="$(val SafeMode)"
      DUPES=$(grep -c '^DisableCloud:' "$CFG")
    fi
    NETSOOK_PRESENT=0
    [ -f "$NETSOOK" ] && NETSOOK_PRESENT=1

    # -- Injection fork (live Steam process) --------------------------------
    # LD_AUDIT lands in the env of every process Steam launches; scan /proc
    # for one carrying it and see which fork is injected. Store names differ:
    # upstream builds as "sls-steam", the fork as "slsteam-moon".
    INJECTION="unknown (Steam not running)"
    if ${pkgs.procps}/bin/pgrep -x steam >/dev/null 2>&1 \
      || ${pkgs.procps}/bin/pgrep -x steamwebhelper >/dev/null 2>&1; then
      INJECTION="none"
      LD=""
      for p in /proc/[0-9]*/environ; do
        [ -r "$p" ] || continue
        LD="$(tr '\0' '\n' < "$p" 2>/dev/null | grep -m1 '^LD_AUDIT=' || true)"
        [ -n "$LD" ] && break
      done
      case "$LD" in
        *slsteam-moon*) INJECTION="slsteam-moon (LuaTools)" ;;
        *sls-steam*)    INJECTION="upstream SLSsteam" ;;
      esac
    fi

    # -- Games (slsteam-moon / LuaTools) ------------------------------------
    # slsteam-moon does NOT write added games into config.yaml's AdditionalApps
    # (that section is deprecated). Games are <appid>.lua files in Steam's
    # stplug-in dir, plus manual appids in luaappids.yaml.
    STPLUG=""
    for root in "$HOME/.steam/steam" "$HOME/.steam/debian-installation" "$HOME/.local/share/Steam"; do
      if [ -d "$root/config/stplug-in" ]; then STPLUG="$root/config/stplug-in"; break; fi
    done
    LUA_COUNT=0
    if [ -n "$STPLUG" ]; then
      LUA_COUNT=$(find "$STPLUG" -maxdepth 1 -name '*.lua' 2>/dev/null | wc -l | tr -d ' ')
    fi
    LUAAPPIDS=0
    [ -f "$HOME/.config/SLSsteam/luaappids.yaml" ] && LUAAPPIDS=1

    # -- CloudRedirect -------------------------------------------------------
    CR_ENABLED=0
    case "$DISABLECLOUD" in
      no | false) CR_ENABLED=1 ;;
    esac
    CR_HOOK="missing"
    if [ -e "$CRLINK" ]; then
      CR_TARGET="$(readlink -f "$CRLINK" 2>/dev/null || true)"
      case "$CR_TARGET" in
        "$CR_MOON") CR_HOOK="moon (LuaTools)" ;;
        "$CR_UP")   CR_HOOK="upstream" ;;
        *)          CR_HOOK="other: $CR_TARGET" ;;
      esac
    fi
    CR_CLI=0
    [ -x "$HOME/.local/share/CloudRedirect/cloud_redirect_lib" ] && CR_CLI=1
    CR_FLATPAK=0
    [ -d "$HOME/.local/share/flatpak/app/org.cloudredirect.CloudRedirect" ] && CR_FLATPAK=1

    # -- LuaTools / Lumen ----------------------------------------------------
    L_INSTALLED=0
    [ -x "$LUMEN_DIR/lumen" ] && [ -x "$LUMEN_DIR/lumen.bin" ] && L_INSTALLED=1
    L_PLUGIN=0
    [ -d "$LUMEN_DIR/luatools/backend" ] && L_PLUGIN=1
    L_RUNNING=0
    ${pkgs.procps}/bin/pgrep -f "$LUMEN_DIR/lumen.bin" >/dev/null 2>&1 && L_RUNNING=1
    L_CEFPORT=0
    [ -f "$LUMEN_DIR/cef_port" ] && L_CEFPORT=1

    # -- Updates --------------------------------------------------------------
    UPDATES_BLOCKED=0
    [ -f "$STEAMCFG" ] && UPDATES_BLOCKED=1

    if [ "$MODE" = "json" ]; then
      printf '{'
      printf '"steam":{"version":%s,"manifest_note":%s,"updates_blocked":%s},' \
        "$(json_str "$STEAM_VERSION")" "$(json_str "$STEAM_NOTE")" "$(json_bool "$UPDATES_BLOCKED")"
      printf '"slssteam":{"config_present":%s,"disable_cloud":%s,"play_not_owned":%s,"safe_mode":%s,"disable_cloud_duplicates":%s,"netsock_present":%s},' \
        "$(json_bool "$CONFIG_PRESENT")" "$(json_str "$DISABLECLOUD")" "$(json_str "$PLAYNOTOWNED")" "$(json_str "$SAFEMODE")" "$DUPES" "$(json_bool "$NETSOOK_PRESENT")"
      printf '"injection":%s,' "$(json_str "$INJECTION")"
      printf '"games":{"stplug_in_dir":%s,"lua_manifests":%s,"luaappids_yaml":%s},' \
        "$(json_str "$STPLUG")" "$LUA_COUNT" "$(json_bool "$LUAAPPIDS")"
      printf '"cloudredirect":{"enabled":%s,"hook":%s,"cli_present":%s,"flatpak_installed":%s},' \
        "$(json_bool "$CR_ENABLED")" "$(json_str "$CR_HOOK")" "$(json_bool "$CR_CLI")" "$(json_bool "$CR_FLATPAK")"
      printf '"luatools":{"installed":%s,"plugin_installed":%s,"running":%s,"cef_port":%s}' \
        "$(json_bool "$L_INSTALLED")" "$(json_bool "$L_PLUGIN")" "$(json_bool "$L_RUNNING")" "$(json_bool "$L_CEFPORT")"
      printf '}\n'
      exit 0
    fi

    echo "=== Steam Client ==="
    if [ -n "$STEAM_VERSION" ] && [ "$STEAM_VERSION" != "unknown" ]; then
      echo "Version: $STEAM_VERSION"
    else
      echo "Version: unknown (no manifest in $PKG)"
    fi

    echo
    echo "=== SLSsteam ==="
    if [ "$CONFIG_PRESENT" = 1 ]; then
      echo "DisableCloud:   $DISABLECLOUD"
      echo "PlayNotOwned:   $PLAYNOTOWNED"
      echo "SafeMode:       $SAFEMODE"
      [ "$DUPES" -gt 1 ] && echo "Warning:        DisableCloud set $DUPES times - only the last counts"
    else
      echo "Config missing: $CFG"
    fi
    echo "Netsock:        $([ "$NETSOOK_PRESENT" = 1 ] && echo present || echo missing)"

    echo
    echo "=== Injection (live Steam) ==="
    echo "Fork:           $INJECTION"

    echo
    echo "=== Games (slsteam-moon / LuaTools) ==="
    if [ -n "$STPLUG" ]; then
      echo "stplug-in:      $LUA_COUNT lua manifests ($STPLUG)"
    else
      echo "stplug-in:      missing (no Steam root with config/stplug-in)"
    fi
    if [ "$LUAAPPIDS" = 1 ]; then
      echo "luaappids.yaml: present (manual AdditionalApps list)"
    else
      echo "luaappids.yaml: none"
    fi

    echo
    echo "=== CloudRedirect ==="
    # Both spellings: SLSsteam and SteaMidra write YAML 1.2 true/false, a
    # hand-edited or headcrab-era config carries YAML 1.1 yes/no.
    if [ "$CR_ENABLED" = 1 ]; then
      echo "Status: Enabled (DisableCloud: $DISABLECLOUD)"
    else
      echo "Status: Disabled"
    fi
    echo "Hook:           $CR_HOOK"
    echo "CLI:            $([ "$CR_CLI" = 1 ] && echo present || echo missing)"
    echo "Flatpak:        $([ "$CR_FLATPAK" = 1 ] && echo installed || echo not installed)"

    echo
    echo "=== LuaTools / Lumen ==="
    if [ "$L_INSTALLED" = 1 ]; then
      echo "Lumen:          installed"
    else
      echo "Lumen:          not installed (luatools.enable off?)"
    fi
    echo "Plugin:         $([ "$L_PLUGIN" = 1 ] && echo installed || echo missing)"
    echo "Running:        $([ "$L_RUNNING" = 1 ] && echo yes || echo no)"
    echo "CEF endpoint:   $([ "$L_CEFPORT" = 1 ] && echo attached || echo "waiting (restart Steam after the first switch)")"

    echo
    echo "=== Client-Updates ==="
    if [ -f "$STEAMCFG" ]; then
      echo "steam.cfg present -> client updates blocked"
    else
      echo "no steam.cfg -> client follows updates"
    fi
  '';

  # Convenience wrapper: update the consumer flake's inputs, rebuild through
  # whatever switcher is installed, then print the fresh status.
  nixCrabUpdate = pkgs.writeShellScriptBin "nix-crab-update" ''
    set -u

    if [ ! -f flake.nix ]; then
      echo "nix-crab-update: no flake.nix in $PWD - run from your configuration repo" >&2
      exit 1
    fi

    echo "== nix flake update =="
    nix flake update || exit 1

    if command -v nh >/dev/null 2>&1; then
      echo "== nh os switch =="
      nh os switch || echo "nh os switch failed (see output above)" >&2
      echo "== nh home switch =="
      nh home switch || echo "nh home switch failed (see output above)" >&2
    elif command -v nixos-rebuild >/dev/null 2>&1; then
      echo "== nixos-rebuild switch =="
      sudo nixos-rebuild switch --flake . || echo "nixos-rebuild failed (see output above)" >&2
      if command -v home-manager >/dev/null 2>&1; then
        echo "== home-manager switch =="
        home-manager switch --flake . || echo "home-manager switch failed (see output above)" >&2
      fi
    else
      echo "nix-crab-update: neither nh nor nixos-rebuild found - inputs updated, nothing switched" >&2
    fi

    echo
    echo "== nix-crab-status =="
    if command -v nix-crab-status >/dev/null 2>&1; then
      nix-crab-status || true
    else
      echo "nix-crab-status not on PATH (home module not enabled?)"
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

    home.packages = [cloudredirectCli nixCrabStatus nixCrabUpdate];
  };
}
