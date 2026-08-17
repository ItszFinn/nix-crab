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
    # Upstream CloudRedirect hook — the default. Reads the game list from
    # config.yaml's AdditionalApps.
    cloudredirect = {
      type = "file";
      url = "https://github.com/Selectively11/CloudRedirect/releases/latest/download/cloud_redirect.so";
      flake = false;
    };
    # Optional hook for the LuaTools stack, opt-in via
    # programs.nix-crab.cloudredirect.moon. Upstream's cloud_redirect.so only
    # reads config.yaml's AdditionalApps, which slsteam-moon deprecated (games
    # now live as <appid>.lua files in <Steam>/config/stplug-in/). This fork
    # additionally scans stplug-in + luaappids.yaml. The .so is committed at
    # the repo root.
    cloudredirect-moon = {
      url = "github:swwayps/cloudredirect-moon";
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
    # SLSsteam fork with a native Lua manifest importer (the maintained path
    # for the LuaTools workflow on Linux). No flake, so it is built from source
    # in modules/slssteam.nix instead of being imported as a package set.
    slsteam-moon = {
      url = "github:swwayps/slsteam-moon";
      flake = false;
    };
    # Lumen (static Lua backend) + the LuaTools plugin port, both from the
    # slsteam-moon maintainer. Pinned by git rev, not the versionless
    # releases/latest URLs (those change content on every release and break
    # the lock's narHash). Lumen's portable binary is committed at
    # dist/lumen-linux.zip; the plugin is built from its plugin/ source tree.
    lumen = {
      url = "github:swwayps/lumen";
      flake = false;
    };
    luatools-moon = {
      url = "github:swwayps/luatools-moon";
      flake = false;
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
    cloudredirect-moon,
    cloudredirect-cli,
    millennium,
    nix-flatpak,
    nixpkgs,
    self,
    sls-steam,
    slsteam-moon,
    lumen,
    luatools-moon,
    steamidra,
    steamnetsock,
  }: {
    nixosModules.default = {
      imports = [
        (import ./modules/millennium.nix {inherit millennium;})
        (import ./modules/cloudredirect.nix {inherit cloudredirect cloudredirect-moon;})
        (import ./modules/slssteam.nix {inherit sls-steam slsteam-moon;})
        ./modules/downgrade.nix
      ];
    };

    homeModules.default = {
      imports = [
        (import ./modules/home.nix {inherit sls-steam nix-flatpak steamnetsock cloudredirect cloudredirect-moon cloudredirect-cli;})
        ./modules/millennium-addons.nix
        (import ./modules/luatools-moon.nix {inherit lumen luatools-moon;})
        (import ./modules/steamidra.nix {inherit steamidra;})
        (import ./modules/accela.nix {inherit accela;})
      ];
    };
  };
}
