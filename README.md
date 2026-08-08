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

The CloudRedirect desktop app reports **"SLSsteam not found"** and **"CloudRedirect not deployed"** —
this is normal and does not change after launching Steam. The app's status readout does not reflect
the session injection from this flake; it just means CloudRedirect did not run inside a Steam session
that this app can see. The actual `LD_AUDIT`/`LD_PRELOAD` injection works regardless.

CloudRedirect only syncs if `DisableCloud: no` is set in `~/.config/SLSsteam/config.yaml` (this
flake ships exactly that via the `services.sls-steam.config` default). If you set
`DisableCloud: yes`, the app will show "CloudRedirect not deployed" and cloud saves stop working.

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

This installs the packaged .NET 9 AppImage with sandboxing disabled for QtWebEngine, proper icon integration, and a desktop entry (`steamidra`). If you use SteaMidra alongside Nix-managed config, set `programs.nix-crab.slssteam.manageConfig = true;` or leave it unmanaged (`false`, the default) so SteaMidra can update `config.yaml` directly.

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
