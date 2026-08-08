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
    nix-crab.url = "github:your-user/nix-crab";
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
    # programs.nix-crab.downgrade.enable = true;  # optional
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

| Option                                      | Description                                                                                             |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `programs.nix-crab.slssteam.manageConfig`   | Whether Nix manages `~/.config/SLSsteam/config.yaml` (default `false`, leaving the file unmanaged so external tools like SteaMidra can edit it). |
| `programs.nix-crab.steamidra.enable`        | Enable SteaMidra (SFF) desktop app (.NET 9 AppImage wrapper with desktop entry and icon).                |

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

**"CloudRedirect: Not deployed"** stays and is harmless: "deploy" means copying the bundled `.so`
into place and patching `steam.sh`, which this flake replaces with `LD_PRELOAD` from the pinned
flake input. Injection works regardless — check `~/.config/CloudRedirect/cr_debug.log` for
`DoInit: SUCCESS`.

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

## Credits

A huge thank you to the developers of the projects that make this declarative NixOS reproduction possible.

This repository was created and is maintained by a **13-year-old NixOS enthusiast** (who knows that while this project's setup is anything but optimal, it works perfectly and gets the job done!), developed and polished with the help of the **[opencode](https://github.com/anomalyco/opencode)** AI assistant.

Project Credits:
- **[SLSsteam](https://github.com/AceSLS/SLSsteam)** (by AceSLS) — for the incredible Steam injection capability.
- **[CloudRedirect](https://github.com/Selectively11/CloudRedirect)** (by Selectively11) — for the reliable cloud save syncing.
- **[SteaMidra (SFF)](https://github.com/Midrags/SFF)** (by Midrags) — for the powerful configuration and account manager.
- **[steamnetsock-patch](https://github.com/yesyes0649/steamnetsock-patch)** (by yesyes0649) — for the multiplayer fixes.
