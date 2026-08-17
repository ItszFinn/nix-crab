{
  sls-steam,
  slsteam-moon,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.nix-crab;

  upstream = sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.sls-steam;

  # slsteam-moon is a fork of SLSsteam that produces the same two artefacts
  # (SLSsteam.so + library-inject.so) plus a native Lua manifest importer. It
  # ships no flake, so it is built from source with the same 32-bit toolchain
  # upstream uses in its own nix-modules/default.nix.
  slsteamMoon = pkgs.pkgsi686Linux.stdenv.mkDerivation {
    pname = "slsteam-moon";
    version = "0.0.0";
    src = slsteam-moon;
    nativeBuildInputs = with pkgs; [pkg-config];
    buildInputs = with pkgs.pkgsi686Linux; [openssl curl];
    # pattern-refresh is a native host helper we don't need; only the two
    # Steam-loaded i386 objects are injected.
    buildPhase = "make bin/SLSsteam.so bin/library-inject.so";
    # -O3 -flto over ~100 translation units; the Makefile only marks `clean`
    # and `rebuild` as .NOTPARALLEL, so the object targets take -j fine.
    enableParallelBuilding = true;
    installPhase = ''
      mkdir -p "$out"
      cp bin/SLSsteam.so "$out/"
      cp bin/library-inject.so "$out/"
    '';
    meta = {
      description = "SLSsteam fork with a Lua manifest importer (slsteam-moon)";
      homepage = "https://github.com/swwayps/slsteam-moon";
      license = lib.licenses.agpl3Only;
      platforms = lib.platforms.linux;
    };
  };

  # Both forks ship the same two artefacts under the same names, so the choice
  # is one store path, not two branches of wiring.
  sls =
    if cfg.slssteam-moon.enable
    then slsteamMoon
    else upstream;
in {
  options.programs.nix-crab = {
    slssteam.enable = lib.mkEnableOption "SLSsteam (upstream) injection into Steam";

    slssteam.extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables injected into Steam";
    };

    slssteam-moon.enable = lib.mkEnableOption ''
      slsteam-moon (SLSsteam fork with a Lua manifest importer) instead of
      upstream SLSsteam. Takes precedence over slssteam.enable; required by
      the home module's luatools option.
    '';
  };

  config = lib.mkIf (cfg.slssteam.enable || cfg.slssteam-moon.enable) {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        extraEnv =
          {
            LD_AUDIT = "${sls}/library-inject.so:${sls}/SLSsteam.so";
          }
          // cfg.slssteam.extraEnv;
      };
    };
  };
}
