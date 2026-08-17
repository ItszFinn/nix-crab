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

  config = lib.mkIf config.programs.nix-crab.cloudredirect.enable {
    services.flatpak.enable = true;
    programs.nix-crab.slssteam.extraEnv.LD_PRELOAD =
      if config.programs.nix-crab.cloudredirect.moon.enable
      then "${cloudredirect-moon}/cloud_redirect.so"
      else "${cloudredirect}";
  };
}
