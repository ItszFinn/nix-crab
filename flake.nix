{
  description = "Flake for h3adcr-b on NixOS";

  inputs = {
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
      url = "https://api.github.com/repos/Midrags/SFF/releases/latest";
      flake = false;
      narHash = "sha256-e1BunPItO4rUpXXWPyrgadT4DtetMQWCEM9wLr1YmdQ=";
    };
  };

  outputs = {self, nixpkgs, sls-steam, cloudredirect, cloudredirect-cli, nix-flatpak, steamnetsock, steamidra}: {
    nixosModules.default = {
      imports = [
        (import ./modules/slssteam.nix {inherit sls-steam;})
        (import ./modules/cloudredirect.nix {inherit cloudredirect;})
        ./modules/downgrade.nix
      ];
    };

    homeModules.default = {
      imports = [
        (import ./modules/home.nix {inherit sls-steam nix-flatpak steamnetsock cloudredirect-cli;})
        (import ./modules/steamidra.nix {inherit steamidra;})
      ];
    };
  };
}
