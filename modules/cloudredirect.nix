{
  cloudredirect,
}: {
  config,
  lib,
  ...
}: {
  options.programs.nix-crab.cloudredirect.enable =
    lib.mkEnableOption "Enable CloudRedirect";

  config = lib.mkIf config.programs.nix-crab.cloudredirect.enable {
    services.flatpak.enable = true;
    programs.nix-crab.slssteam.extraEnv.LD_PRELOAD = "${cloudredirect}";
  };
}
