{
  sls-steam,
}: {
  config,
  lib,
  pkgs,
  ...
}: {
  options.programs.nix-crab.slssteam = {
    enable = lib.mkEnableOption "Enable SLSsteam";

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables injected into Steam";
    };
  };

  config = lib.mkIf config.programs.nix-crab.slssteam.enable {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        extraEnv = let
          slssteam = sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.sls-steam;
        in {
          LD_AUDIT = "${slssteam}/library-inject.so:${slssteam}/SLSsteam.so";
        } // config.programs.nix-crab.slssteam.extraEnv;
      };
    };
  };
}
