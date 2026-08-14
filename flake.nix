{
  description = "Flake for h3adcr-b on NixOS";

  inputs = {
    accela = {
      type = "file";
      # Enter The Wired's bundle, which ships the AppImage. Versionless URL, so
      # unlike steamidra it needs no tag-list indirection and no pinned hash.
      url = "https://github.com/ciscosweater/enter-the-wired/releases/download/latest/deps.tar.gz";
      flake = false;
    };
    cloudredirect = {
      type = "file";
      url = "https://github.com/Selectively11/CloudRedirect/releases/latest/download/cloud_redirect.so";
      flake = false;
    };
    cloudredirect-cli = {
      type = "file";
      url = "https://github.com/Selectively11/h3adcr-b/releases/download/linux-test/cloud_redirect_cli";
      flake = false;
    };
    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sls-steam = {
      url = "github:AceSLS/SLSsteam";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    steamnetsock = {
      type = "file";
      url = "https://github.com/yesyes0649/steamnetsock-patch/releases/latest/download/fix.so";
      flake = false;
    };
    steamidra = {
      type = "file";
      # Tag list, not releases/latest: that JSON embeds per-asset download
      # counters, so its narHash changes within the hour and every eval after
      # the tarball TTL dies with a narHash mismatch. /tags only changes when a
      # new tag is pushed. `nix flake update` follows the newest release.
      url = "https://api.github.com/repos/Midrags/SFF/tags";
      flake = false;
    };
  };

  outputs = {
    accela,
    cloudredirect,
    cloudredirect-cli,
    millennium,
    nix-flatpak,
    nixpkgs,
    self,
    sls-steam,
    steamidra,
    steamnetsock,
  }: {
    nixosModules.default = {
      imports = [
        (import ./modules/millennium.nix {inherit millennium;})
        (import ./modules/cloudredirect.nix {inherit cloudredirect;})
        (import ./modules/slssteam.nix {inherit sls-steam;})
        ./modules/downgrade.nix
      ];
    };

    homeModules.default = {
      imports = [
        (import ./modules/home.nix {inherit sls-steam nix-flatpak steamnetsock cloudredirect cloudredirect-cli;})
        ./modules/millennium-addons.nix
        (import ./modules/steamidra.nix {inherit steamidra;})
        (import ./modules/accela.nix {inherit accela;})
      ];
    };
  };
}
