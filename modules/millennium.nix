{millennium}: {
  config,
  lib,
  ...
}: let
  cfg = config.programs.nix-crab.millennium;
  system = "x86_64-linux";
  upstreamPkgs = import millennium.inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  baselineBun = upstreamPkgs.bun.overrideAttrs (old: {
    src = upstreamPkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${old.version}/bun-linux-x64-baseline.zip";
      hash = "sha256-nYokKSpwaAkCBdqsCloiP19pc29Sh+N7+I07QDHtx1A=";
    };
    sourceRoot = "bun-linux-x64-baseline";
  });
in {
  options.programs.nix-crab.millennium = {
    enable = lib.mkEnableOption "Enable millennium";
    bunBaseline = lib.mkEnableOption "Use the Bun baseline build (no AVX2 required) for Millennium's bun dependency install";
  };

  config = lib.mkIf cfg.enable {
    # Not programs.steam.package: slssteam.nix defines that too, and two
    # definitions are an eval error. As an overlay Millennium becomes the base
    # that slssteam's steam.override extends -- its steam.nix merges
    # (extraEnv // millenniumEnv), so LD_AUDIT survives.
    nixpkgs.overlays = [
      millennium.overlays.default

      # Upstream's overlay only exposes millennium-steam, closed over its own
      # millennium package. Rebuild the Steam wrapper with the overridden bun
      # argument so bunDeps (and the 32-bit build) actually use baseline Bun.
      (final: prev: lib.optionalAttrs cfg.bunBaseline {
        millennium-steam = upstreamPkgs.callPackage "${millennium}/steam.nix" {
          millennium = millennium.packages.${system}.millennium.override {bun = baselineBun;};
        };
      })

      (final: prev: {steam = final.millennium-steam;})
    ];
  };
}
