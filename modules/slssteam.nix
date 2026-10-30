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
  slsRaw =
    if cfg.slssteam-moon.enable
    then slsteamMoon
    else upstream;

  # The prebuilt audit objects carry a RUNPATH onto their own glibc/libstdc++
  # (glibc-2.42-67 + gcc-15.3.0-lib). Steam's FHS env already has a 32-bit
  # libc loaded (glibc-multi-2.42-61 + gcc-15.2.0-lib), and the loader honours
  # that RUNPATH: a second libc.so.6 ends up in the same 32-bit process. The
  # canary is then written by one libc and verified by the other, so every
  # 32-bit program dies with "*** stack smashing detected ***".
  # Dropping the RUNPATH makes the loader reuse the already-loaded libc; the
  # direct NEEDED (openssl, curl) stay reachable through the store paths below.
  sls = pkgs.runCommand "SLSsteam-audit" {
    nativeBuildInputs = [pkgs.patchelf];
  } ''
    mkdir -p "$out"
    cp ${slsRaw}/library-inject.so "$out/"
    cp ${slsRaw}/SLSsteam.so "$out/"
    chmod u+w "$out"/*.so
    patchelf --remove-rpath "$out/library-inject.so"
    patchelf --remove-rpath "$out/SLSsteam.so"
  '';
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
        # The FHS wrapper never binds /sys: bubblewrap starts with a fresh
        # mount namespace where /sys does not exist, and the auto-mount loop
        # cannot bind a mountpoint onto itself. Mesa then cannot resolve
        # /sys/dev/char/226:* or /sys/class/drm, reports "failed to retrieve
        # device information", refuses to load i915/iris and falls back to
        # llvmpipe. Steam's 32-bit vgui2 gets no GLX visual and fatal-asserts
        # with "glXChooseVisual failed". A read-only bind is all it needs.
        extraBwrapArgs = ["--ro-bind /sys /sys"];
      };
    };
  };
}
