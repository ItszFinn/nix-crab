# nix-crab

Declarative [h3adcr-b](https://github.com/Deadboy666/h3adcr-b/)-equivalent for NixOS.
Installs and wires up [SLSsteam](https://github.com/AceSLS/SLSsteam) (play unlocked/not-owned games),
[CloudRedirect](https://github.com/Selectively11/CloudRedirect) (cloud saves for non-owned/"lua" games)
and the optional [steamnetsock-patch](https://github.com/yesyes0649/steamnetsock-patch) (multiplayer fix),
plus a client-downgrade tool — all from a single flake.

## Features

- **SLSsteam** injected into the native Steam package via `LD_AUDIT` (`programs.steam` override) — no
  runtime patching of `steam.sh`.
- **CloudRedirect** installed as a Flatpak (declaratively via `nix-flatpak`) and injected with
  `LD_PRELOAD`.
- **netsock** (steamnetsock-patch) placed at `~/.config/SLSsteam/tools/netsock/netsock.so` for use as a
  per-game launch option.
- **CloudRedirect CLI** (`cloud_redirect_cli`) available on `PATH` and at
  `~/.local/share/CloudRedirect/cloud_redirect_lib`.
- **SteaMidra (SFF)** (optional) — .NET 9 AppImage for managing Steam accounts, tokens and configuration.
- **ACCELA** (optional) — Qt depot-downloader GUI from the Enter The Wired bundle, configured to hand
  its games to SLSsteam.
- **Millennium** (optional) — Steam client modding framework (themes/plugins), applied as a `pkgs.steam`
  overlay so it stacks with the SLSsteam injection instead of fighting it.
- **Client downgrade** (`nix-crab-downgrade`) — pins the Steam client to headcrab's compatible build
  using `dlm` + `dgsc` + `-overridepackageurl`.
- **`nix-crab-status`** — diagnostic command showing client version, SLSsteam config, netsock,
  CloudRedirect status and update-blocking state.
- **Zero-maintenance updates** — by default the Steam client is _not_ frozen: it follows updates on its
  own, and SLSsteam/CloudRedirect/netsock can be updated instantly by running `nix flake update` in your own configuration.

## Installation

Add the flake as an input:

```nix
{
  inputs = {
    nix-crab.url = "github:ItszFinn/nix-crab";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
}
```

### NixOS module

```nix
modules = [
  nix-crab.nixosModules.default
  {
    programs.nix-crab.slssteam.enable = true;
    programs.nix-crab.cloudredirect.enable = true;
    # programs.nix-crab.millennium.enable = true;  # optional
    # programs.nix-crab.downgrade.enable = true;   # optional
  }
];
```

### Home Manager module

```nix
modules = [
  nix-crab.homeModules.default
];
```

Both modules must be imported: the NixOS module injects SLSsteam/CloudRedirect into Steam, the home
module provides the SLSsteam config (`~/.config/SLSsteam/config.yaml`), netsock, the CloudRedirect
CLI and installs `org.cloudredirect.CloudRedirect` as a user Flatpak. Import both in one switch so
they stay in sync.

## Options

### `nixosModules.default`

| Option                                   | Description                                                                                                |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `programs.nix-crab.slssteam.enable`      | Enable SLSsteam injection into the native Steam package. Implies `programs.steam.enable = true`.           |
| `programs.nix-crab.slssteam.extraEnv`    | Extra environment variables merged into the Steam override (used by CloudRedirect for `LD_PRELOAD`).       |
| `programs.nix-crab.cloudredirect.enable` | Enable CloudRedirect: enables the Flatpak service and sets `LD_PRELOAD` to the pinned `cloud_redirect.so`. |
| `programs.nix-crab.millennium.enable`    | Replace `pkgs.steam` with `millennium-steam` via overlay. Combine with `slssteam.enable`.                   |
| `programs.nix-crab.downgrade.enable`     | Add the `nix-crab-downgrade` script to `environment.systemPackages`.                                       |
| `programs.nix-crab.downgrade.package`    | Override the wrapper script.                                                                               |

### `homeModules.default`

The home module imports the upstream typed `services.sls-steam.config` option (so every SLSsteam
setting is available with proper types) and ships the headcrab-compatible defaults
(`PlayNotOwnedGames: yes`, `DisableCloud: no`, `SafeMode: no`). The generated `config.yaml` renders
YAML 1.1 `yes`/`no` booleans (headcrab greps the literal `DisableCloud: no`). It also configures:

- `services.flatpak` — remotes `flathub` + `cloudredirect`, package `org.cloudredirect.CloudRedirect`.
- `home.file` — netsock and the CloudRedirect CLI.
- `home.packages` — `cloud_redirect_cli` and `nix-crab-status`.

| Option                                    | Description                                                                                                                                      |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `programs.nix-crab.slssteam.manageConfig` | Whether Nix manages `~/.config/SLSsteam/config.yaml` (default `false`, leaving the file unmanaged so external tools like SteaMidra can edit it). |
| `programs.nix-crab.steamidra.enable`      | Enable SteaMidra (SFF) desktop app (.NET 9 AppImage wrapper with desktop entry and icon).                                                        |
| `programs.nix-crab.accela.enable`         | Enable ACCELA desktop app (Enter The Wired AppImage with desktop entry, icon and a seeded `ACCELA.conf`).                                        |
| `programs.nix-crab.millennium.plugins`    | Millennium plugin IDs from [steambrew.app/plugins](https://steambrew.app/plugins); installed into `~/.local/share/millennium/plugins`.           |
| `programs.nix-crab.millennium.themes`     | Millennium themes from [steambrew.app/themes](https://steambrew.app/themes) by ID, name or repo; installed into `~/.steam/steam/millennium/themes`. |

## Updating

```
nix flake update
sudo nixos-rebuild switch   # or: home-manager switch
```

That is all. SLSsteam, CloudRedirect, netsock and the CloudRedirect CLI all track their upstream
releases through the locked inputs. The Steam client updates itself on next launch.

> **Note:** If a Steam client update briefly breaks SLSsteam, the SLSsteam project usually fixes it
> quickly — the next `nix flake update` picks the fix up. The `config.yaml` deliberately sets
> `SafeMode: no` (SafeMode is intended for Steam Deck gamemode and can wrongly disable SLSsteam on
> desktop).

## CloudRedirect app status

The app's "SLSsteam" row is a prerequisite check for the imperative h3adcr-b layout: it stats
`~/.local/share/SLSsteam/SLSsteam.so`. Nix keeps SLSsteam in the store, so the home module links it
to that path and grants the Flatpak `/nix/store:ro` (otherwise the symlink dangles inside the
sandbox) — the app then shows **"SLSsteam: Installed"**.

The CloudRedirect row works the same way: the app's deploy check stats
`~/.local/share/CloudRedirect/cloud_redirect.so` and otherwise reports **"failed to deploy"**. The
home module links that path to the pinned flake input — the same `.so` that
`modules/cloudredirect.nix` puts in `LD_PRELOAD`, so there is only ever one library.

What the app's own "deploy" would do beyond that — patching `steam.sh` — this flake does not need;
injection comes from `LD_PRELOAD`. Verify it with `DoInit: SUCCESS` in
`~/.config/CloudRedirect/cr_debug.log`. Don't press deploy in the app: the linked `.so` is
read-only in the store, so the app cannot write over it.

CloudRedirect only syncs if `DisableCloud: no` is set in `~/.config/SLSsteam/config.yaml`. Careful
with duplicate keys: SLSsteam's yaml-cpp lets the **last** occurrence win, and SteaMidra appends a
second flat key block to the file — so a `DisableCloud: no` at the top can be silently overridden by
a `DisableCloud: yes` further down. `nix-crab-status` reads the last occurrence and warns about
duplicates.

## Client downgrade (optional)

If you want to pin the Steam client to headcrab's compatible build instead of following updates:

```nix
programs.nix-crab.downgrade.enable = true;
```

Then run:

```
nix-crab-downgrade
```

This mirrors headcrab's flow: it writes the update-blocking `steam.cfg`, downloads the client
manifest, fetches the pinned client files with `dlm`, serves them with `dgsc` on `:1666` and applies
them via `steam -forcesteamupdate -forcepackagedownload -overridepackageurl http://localhost:1666/`.

> The downgrade is inherently pinned to a specific Steam build (`sources.txt`). Only use it if you
> explicitly want to freeze the client.

## netsock (multiplayer fix)

netsock fixes multiplayer in a few games that use SteamNetworkingSockets with SLSsteam's
`FakeAppIds`. It is **not** injected globally — set it as a **per-game launch option** in Steam:

```
LD_AUDIT="$HOME/.config/SLSsteam/tools/netsock/netsock.so" %command%
```

> **Never use netsock with anti-cheat games** — it scans and modifies game memory.

## nix-crab-status

```
nix-crab-status
```

Prints the Steam client version, SLSsteam config values, netsock presence, CloudRedirect status
(Flatpak + CLI) and whether client updates are blocked.

## SteaMidra (optional GUI)

If you want to use [SteaMidra (SFF)](https://github.com/Midrags/SFF) to manage Steam accounts, tokens and settings:

```nix
programs.nix-crab.steamidra.enable = true;
```

The release version comes from the `steamidra` flake input (GitHub's tag list), but the 520 MiB
AppImage is _not_ fetched by Nix: SFF has no versionless asset URL, so a Nix fetch would need a
hand-bumped SRI hash for every release. Instead the `steamidra` launcher downloads and unpacks
exactly the locked version into `~/.local/share/SteaMidra/` on first run (with a desktop
notification), then runs it through `appimage-run` with QtWebEngine sandboxing disabled. After
`nix flake update` the next launch picks up the new version. The desktop icon appears after that
first run. If you use SteaMidra alongside Nix-managed config, set `programs.nix-crab.slssteam.manageConfig = true;` or leave it unmanaged (`false`, the default) so SteaMidra can update `config.yaml` directly.

## Millennium (optional)

[Millennium](https://github.com/SteamClientHomebrew/Millennium) adds themes and plugins to the Steam
client:

```nix
programs.nix-crab.millennium.enable = true;
```

It is applied as an overlay (`steam = millennium-steam`), not as `programs.steam.package` — that
option is already defined by the SLSsteam module, and a second definition is an eval error. As the
overlay only swaps the base package, `modules/slssteam.nix` keeps overriding it, and Millennium's own
`steam.nix` merges rather than replaces (`extraEnv // millenniumEnv`). The resulting Steam carries
`LD_AUDIT` (SLSsteam), `LD_PRELOAD` (CloudRedirect) and `MILLENNIUM_RUNTIME_PATH` at once.

Enable it together with `slssteam.enable`: on its own the module sets the package but not
`programs.steam.enable`, so nothing gets installed.

Two things to expect:

- **No binary cache.** Upstream publishes no substituter, so Millennium is compiled locally — about
  7 minutes for the 32- and 64-bit C++ trees on a 4-core laptop. The first build also pulls a large
  toolchain (rustc, gcc, cmake, bun) and the pinned second nixpkgs, so expect a few GB of downloads
  once; later rebuilds only recompile the three Millennium derivations.
- **The `millennium` input deliberately does not follow this flake's `nixpkgs`.** Upstream pins its
  own nixpkgs commit ("Bun FOD is sensitive to version changes"); following ours would rebuild
  Millennium on every `nix flake update` and risk breaking that fixed-output derivation. The cost is
  a second nixpkgs in the lock and a slightly older Steam wrapper version.

### Plugins and themes

Both are named by the `id` in their store URL — `https://steambrew.app/plugin/3dc714a7c1b1`,
`https://steambrew.app/theme/1wwKwvHrFuzMs7Kb1Uzu` (the store's card menu copies it for you). Themes
also accept their display name or GitHub repo name, whichever is at hand:

```nix
programs.nix-crab.millennium = {
  plugins = [ "3dc714a7c1b1" ];
  themes  = [ "1wwKwvHrFuzMs7Kb1Uzu" ];  # or "Adwaita"
};
```

On activation each entry is resolved against the store index (`/api/v1/plugins` for plugins,
`/api/v2` for themes) and unpacked where Millennium looks for it. Note that those are two different
places on Linux: plugins go to `~/.local/share/millennium/plugins` (its `MILLENNIUM__PLUGINS_PATH`),
themes to `~/.steam/steam/millennium/themes` (its internal `get_millennium_path()`). A stamp in
`~/.local/share/millennium/.nix-crab/` records what was installed, so later switches touch nothing and
hit no network unless you add an entry. Themes additionally get the `metadata.json` (owner, repo,
commit) that Millennium writes itself, so its updater knows what is on disk.

Installing is all this does. Enable the plugin, or pick the theme, once in Millennium's UI afterwards
— both live in a `config.json` that Millennium rewrites, so this flake stays out of it. Millennium
scans these folders at client startup, so restart Steam before looking for a fresh addon.

Take an entry out of the list and the next switch deletes its folder again. Only stamped addons are
touched, so whatever you installed yourself through Millennium's UI stays where it is. The active
theme is not reset — if you remove the theme you are currently using, pick another one in the UI.

Downloaded at activation, not with `fetchzip`: both stores serve an addon's newest commit, so a pinned
hash would break on every upstream release. They also land as real directories rather than store
symlinks, because Millennium writes into these folders.

### Notes

Millennium loads by symlinking its bootstrap over `libXtst.so.6` in `~/.local/share/Steam/ubuntu12_*`.
It does not touch game processes, so it is irrelevant to VAC — but a Steam client update can break the
hook, and untrusted third-party plugins run unsandboxed with your user's rights.

## Comparison to h3adcr-b

| h3adcr-b                                  | nix-crab                                                    |
| ----------------------------------------- | ----------------------------------------------------------- |
| Patches `steam.sh` at runtime             | NixOS `programs.steam` override (`LD_AUDIT` / `LD_PRELOAD`) |
| Downloads binaries on every run           | Pinned, reproducible flake inputs                           |
| Blocking `steam.cfg` always written       | Only written by the optional downgrade script               |
| Auto-downgrade on client version mismatch | Follows client updates; downgrade is opt-in                 |
| Headcrab Updater desktop app              | `nix flake update`                                          |
| Multi-distro support                      | NixOS (native Steam)                                        |

## Caveats

- This is a _reimplementation_ of h3adcr-b for NixOS — not affiliated with h3adcr-b, SLSsteam or
  CloudRedirect.
- CloudRedirect is experimental by nature; back up saves you care about.
- Downloading and running third-party binaries (`dgsc`, `dlm`, `cloud_redirect_cli`) carries the same
  risk as h3adcr-b itself.

## License

MIT — see [LICENSE](LICENSE). Covers this flake's own Nix code only; the upstream projects it wires
up keep their own licenses (SLSsteam is AGPL-3.0).

## Credits

A huge thank you to the developers of the projects that make this declarative NixOS reproduction possible.

This repository was created and is maintained by a **13-year-old NixOS enthusiast** (who knows that while this project's setup is anything but optimal, it works perfectly and gets the job done!), developed and polished with the help of the **[opencode](https://github.com/anomalyco/opencode)** AI assistant.

Project Credits:

- **[SLSsteam](https://github.com/AceSLS/SLSsteam)** (by AceSLS) — for the incredible Steam injection capability.
- **[CloudRedirect](https://github.com/Selectively11/CloudRedirect)** (by Selectively11) — for the reliable cloud save syncing.
- **[SteaMidra (SFF)](https://github.com/Midrags/SFF)** (by Midrags) — for the powerful configuration and account manager.
- **[steamnetsock-patch](https://github.com/yesyes0649/steamnetsock-patch)** (by yesyes0649) — for the multiplayer fixes.
- **[Millennium](https://github.com/SteamClientHomebrew/Millennium)** (by Steam Homebrew) — for the client themes and plugins, and for shipping its own Nix package.
