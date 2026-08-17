# AGENTS.md

NixOS/home-manager flake that reproduces h3adcr-b (SLSsteam + CloudRedirect + optional Steam client downgrade) declaratively.

## Architecture

Hybrid flake with two independent module outputs in `flake.nix`:
- `nixosModules.default` — imports `slssteam.nix` (Steam package override, `LD_AUDIT`), `cloudredirect.nix` (`services.flatpak.enable` + `LD_PRELOAD` via `slssteam.extraEnv`), `downgrade.nix`.
- `homeModules.default` — imports `home.nix` (hand-written `config.yaml`, netsock + CLI via `home.file`, CloudRedirect Flatpak via nix-flatpak, `nix-crab-status`), `steamidra.nix`, `accela.nix`.

Modules are partial applications: `flake.nix` threads flake inputs in via `(import ./modules/x.nix {inherit input;})`. When adding a new module, follow that pattern — do not use `inputs` in the module body.

## Critical decisions (do not "fix" these)

- **`services.sls-steam.config` uses the upstream typed sls-steam home module** (`sls-steam.homeModules.sls-steam`) and lets it generate `config.yaml` as-is — `DisableCloud: false`, YAML 1.2 booleans. There used to be a hand-written yes/no YAML renderer here plus a `lib.mkForce` on the `source` of `xdg.configFile."SLSsteam/config.yaml"`, because headcrab (`h3adcr-b.sh`) grepped the literal `DisableCloud: no`. That script is gone. Readers are `nix-crab-status` **and CloudRedirect's own `.so`** (`src/platform/linux/yaml_parser.h`) — both accept `no` and `false`, so YAML 1.2 is safe. Do not reintroduce the renderer — teach the reader both spellings instead. Both are **last-occurrence-wins**, which is what makes SteaMidra's appended flat key block dangerous (see README, "CloudRedirect app status"). Defaults are `lib.mkDefault`: `PlayNotOwnedGames` on, `DisableCloud` off, `SafeMode` off (SafeMode self-blocks on desktop).
- **`programs.nix-crab.slssteam.manageConfig` defaults to `false`** — `config.yaml` is left unmanaged so tools like SteaMidra that edit the file keep their changes across home-manager switches. The typed module still injects a dead `source`/`text`, but the file's `enable = false` stops it from being written. Set `manageConfig = true` to have Nix write the file again.
- **CloudRedirect stays upstream by default; `cloudredirect-moon` is opt-in.** Upstream's `cloud_redirect.so` reads the game list only from `config.yaml`'s `AdditionalApps`, which slsteam-moon deprecated — LuaTools games live in `<Steam>/config/stplug-in/*.lua`. The `cloudredirect-moon` fork (prebuilt `cloud_redirect.so` committed at its repo root) additionally scans `stplug-in` + `luaappids.yaml`. It is NOT the default: `programs.nix-crab.cloudredirect.moon.enable` (defined in both `cloudredirect.nix` and `home.nix`) switches the `LD_PRELOAD` hook and the `~/.local/share/CloudRedirect/cloud_redirect.so` link. Do not make moon automatic or the default.
- **Two-module design by explicit user request.** The user rejected auto-wiring home-manager into the NixOS module and rejected integration/assertion modules (`homeModuleImported`, `nixosModuleImported`, a `programs.nix-crab.user` option). Do not reintroduce flags, assertions, or `home-manager.nixosModules.home-manager` wiring.
- **Steam client follows updates by default.** `steam.cfg` is only written by the downgrade script (`if [ ! -f ... ]`), not by home.nix.
- **netsock is never injected globally** — it's placed at `~/.config/SLSsteam/tools/netsock/netsock.so` for per-game launch option `LD_AUDIT=...netsock.so %command%`, never with anti-cheat.
- Commands are named `nix-crab-*` (`nix-crab-downgrade`, `nix-crab-status`, internal `nix-crab-dgsc`, `nix-crab-dlm`). External URLs in `downgrade.nix` (e.g. `SteamTracking/.../headcrab/...`) are untouched — only user-facing names changed.

## Verification

- `nix flake check` in repo root — passes when outputs are valid.
- Test harness at `/tmp/opencode/nixcrab-test` (out-of-repo): a flake with `nixosSystem` importing `nixosModules.default` + `homeManagerConfiguration` importing `homeModules.default`. Used to actually evaluate/build both sides (needs `nixpkgs.config.allowUnfree = true` for steam). Re-lock after changing the repo (`rm flake.lock && nix flake lock`), otherwise you get `NAR hash mismatch` for the path input.
- Deep home-manager evals (`config.home-manager.users.<u>.<attr>`) can trip a benign upstream `accounts.calendar.basePath` error; don't chase it.

## Gotchas

- **Path-input narHash**: the user's `~/dotfiles` consumes this via `path:/home/finn/Projects/nix-crab`. After editing here, their `flake.lock` must be updated (`nix flake lock --update-input nix-crab`), otherwise `nh`/`nixos-rebuild` fails with a NAR hash mismatch.
- `downgrade.nix` pins SRI hashes for dgsc/dlm/sources.txt/clientManifest — update them when those upstream files change.
- **The `steamidra` input is `api.github.com/repos/Midrags/SFF/tags`, not `releases/latest`** — the releases JSON embeds per-asset download counters, so its narHash changes within the hour and every eval after the tarball TTL dies with `mismatch in field 'narHash'`. Do not pin `narHash` in `flake.nix` either; that makes the same breakage permanent. `/tags` only changes on a new tag, and the newest tag is the first element.
- **SteaMidra's AppImage is downloaded by the launcher at runtime, not by Nix** — there is no versionless asset URL (`releases/latest/download/SteaMidra-linux.zip` is a 404), so a Nix fetch would need a hand-bumped SRI hash per release, which the user rejected. The flake input supplies the version, the launcher unpacks that version into `~/.local/share/SteaMidra/` and runs it via `appimage-run`. Do not reintroduce `fetchurl` + hash or `appimageTools.wrapType2`.
- **The `accela` input is Enter The Wired's `deps.tar.gz`, not upstream ACCELA.** `froster01/ACCELA` publishes no releases and no tags, and its tree cannot live in the store anyway (chdirs into itself, opens `app.log` with `mode="w"`, resolves assets relative to cwd). The Enter The Wired asset URL is versionless, so this one is a plain flake input with the AppImage in the store — no tag-list indirection, no runtime download.
- **`appimage-run` needs `extraPkgs = p: [p.zstd]`** — the bundled PyQt6 links `libzstd.so.1`, absent from the FHS rootfs. Eval and build pass either way; only launching catches it. Smoke-test: `HOME=$(mktemp -d) QT_QPA_PLATFORM=offscreen accela`.
- **`ACCELA.conf` is seeded, never managed** — QSettings rewrites it, so a store symlink breaks it, same reason as `slssteam.manageConfig`. Seeds only when absent; upstream awk-merges the keys into an existing `[General]`.
- `modules/steam.cfg` `BootStrapperForceSelfUpdate` typo was fixed; keep it `disable`.
- `h3adcr-b.sh` in repo root is reference material only — not part of any build.
