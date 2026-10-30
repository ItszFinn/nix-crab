{
  cloudredirect,
  cloudredirect-moon,
}: {
  config,
  lib,
  ...
}: {
  options.programs.nix-crab.cloudredirect = {
    enable = lib.mkEnableOption "Enable CloudRedirect";

    moon.enable = lib.mkEnableOption ''
      the cloudredirect-moon hook instead of upstream CloudRedirect. The moon
      fork scans <Steam>/config/stplug-in/*.lua and luaappids.yaml, so it
      recognises games added by the LuaTools stack. Only enable for LuaTools;
      upstream CloudRedirect is the default.
    '';
  };

  config = let
    cfg = config.programs.nix-crab;

    # The upstream input is a bare flake input, so its store path is named
    # "-source" and the file inside it has no stable name. LD_PRELOAD takes
    # the path verbatim, so it happens to work, but any rename upstream
    # breaks the hook silently. Stage it under the name the loader, the
    # docs and `cloud_redirect --cli` all expect.
    hook =
      if cfg.cloudredirect.moon.enable
      then "${cloudredirect-moon}/cloud_redirect.so"
      else "${cloudredirect}/cloud_redirect.so";

    hookStaged = pkgs.runCommand "cloud_redirect.so" {} ''
      mkdir -p "$out"
      cp ${hook} "$out/cloud_redirect.so"
    '';
  in
    lib.mkIf cfg.cloudredirect.enable {
      services.flatpak.enable = true;
      programs.nix-crab.slssteam.extraEnv.LD_PRELOAD = "${hookStaged}/cloud_redirect.so";
    };
}
