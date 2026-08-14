{millennium}: {
  config,
  lib,
  ...
}: {
  options.programs.nix-crab.millennium.enable = lib.mkEnableOption "Enable millennium";

  config = lib.mkIf config.programs.nix-crab.millennium.enable {
    # Not programs.steam.package: slssteam.nix defines that too, and two
    # definitions are an eval error. As an overlay Millennium becomes the base
    # that slssteam's steam.override extends -- its steam.nix merges
    # (extraEnv // millenniumEnv), so LD_AUDIT survives.
    nixpkgs.overlays = [
      millennium.overlays.default
      (final: prev: {steam = final.millennium-steam;})
    ];
  };
}
