# grok-bot-nix

Unofficial Nix packaging of the **Grok Bot** Linux desktop app (the official
AppImage). Installs a `grok-bot` command, an application-menu entry and icons,
works from a classic (non-flake) `configuration.nix` as well as from flakes.

> **Unofficial.** Not affiliated with or endorsed by Cursor / xAI. This repo
> contains only Nix code (MIT). The AppImage is downloaded at build time from
> Cursor's CDN (`downloads.cursor.com`) and checked against a pinned hash; it is
> **not** redistributed here. Grok Bot is proprietary (`license = unfree`).
> Official docs: <https://cursor.com/docs/grok-bot/deployment>

Platforms: `x86_64-linux` (tested), `aarch64-linux` (pinned, untested).

## Packages

| attr | what |
|------|------|
| `grok-bot` (default) | Pinned release (`version.json`), hash-verified, built with `appimageTools.wrapType2`. Binary `grok-bot`, `.desktop` entry, hicolor icons. |
| `grok-bot-latest` | **"Always latest at launch"** launcher. Contains no Grok Bot; on every launch it reads Cursor's live release feed, downloads the newest AppImage to `~/.cache/grok-bot/<version>/` (once), and runs it in an FHS env. Binary `grok-bot-latest`, own `.desktop` entry ("Grok Bot (latest)") and icon, so both can be installed side by side. Needs network at launch (falls back to the newest cached version offline); no hash check (the feed publishes none, HTTPS only). |

## Old-style `configuration.nix` (no flakes)

```nix
{ config, pkgs, ... }:
let
  grok-bot = pkgs.callPackage
    (builtins.fetchTarball "https://github.com/ponelat/grok-bot-nix/archive/main.tar.gz") { };
in
{
  nixpkgs.config.allowUnfree = true;   # Grok Bot is unfree

  environment.systemPackages = [ grok-bot ];
  # or the always-latest-at-launch variant:
  # environment.systemPackages = [ grok-bot.latest ];
}
```

Equivalent: `(import (builtins.fetchTarball "https://github.com/ponelat/grok-bot-nix/archive/main.tar.gz") { inherit pkgs; })`.

Then `sudo nixos-rebuild switch`. Every rebuild re-resolves `main`
(`fetchTarball` without a hash is cached for `tarball-ttl`, 1h by default), so
you get whatever version the daily bot bumped to. To **freeze** a revision, pin it:

```sh
nix-prefetch-url --unpack https://github.com/ponelat/grok-bot-nix/archive/<commit>.tar.gz
```
```nix
builtins.fetchTarball {
  url = "https://github.com/ponelat/grok-bot-nix/archive/<commit>.tar.gz";
  sha256 = "<hash printed above>";
}
```

Without NixOS (plain Nix): `NIXPKGS_ALLOW_UNFREE=1 nix-build default.nix` and
`nix-env -if default.nix`.

## Overlay

```nix
{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    (import "${builtins.fetchTarball "https://github.com/ponelat/grok-bot-nix/archive/main.tar.gz"}/overlay.nix")
  ];
  environment.systemPackages = [ pkgs.grok-bot ];   # or pkgs.grok-bot-latest
}
```

(`overlay.nix` is a plain `final: prev: { grok-bot = ...; grok-bot-latest = ...; }`.)

## Flakes

```sh
nix run github:ponelat/grok-bot-nix                      # pinned
nix run github:ponelat/grok-bot-nix#grok-bot-latest      # always latest at launch
nix profile install github:ponelat/grok-bot-nix
```

NixOS flake config:

```nix
{
  inputs.grok-bot.url = "github:ponelat/grok-bot-nix";
  # optional: inputs.grok-bot.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, grok-bot, ... }: {
    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        grok-bot.nixosModules.default      # or overlays.default + systemPackages
        { nixpkgs.config.allowUnfree = true;
          programs.grok-bot.enable = true;
          # programs.grok-bot.latest = true;   # use grok-bot-latest instead
        }
      ];
    };
  };
}
```

`homeManagerModules.default` offers the same `programs.grok-bot.{enable,latest}`
options. The flake's own `packages.*` are built with `allowUnfree = true`;
**your** config still needs `nixpkgs.config.allowUnfree = true` (or an
`allowUnfreePredicate` containing `"grok-bot"` / `"grok-bot-latest"`) when using the
overlay, module or `callPackage` routes.

## Staying up to date

* **Pinned package:** `version.json` holds version, URL and SRI hash per system.
  `./update.sh` reads the live feed
  (`https://api2.cursor.sh/updates/api/download/stable/linux-{x64,arm64}/sand`),
  prefetches the AppImage and rewrites `version.json` (`./update.sh --check` only
  reports). A GitHub Actions workflow (`.github/workflows/update.yml`) runs it
  daily, builds the package, and commits the bump straight to `main`. Then
  `nixos-rebuild switch` (old style) or `nix flake update grok-bot` (flakes).
* **Always latest:** use `grok-bot-latest`; it ignores the pin entirely.

### In-app updater

The AppImage can self-update, which cannot work inside the read-only Nix store.
The wrappers therefore set `SAND_DISABLE_UPDATES=1` (a switch found in the app
itself; override with `SAND_DISABLE_UPDATES=0 grok-bot` if you insist). Updates
come from the bump above or from `grok-bot-latest`.

## Notes

* **Wayland:** set `NIXOS_OZONE_WL=1` (e.g. `environment.sessionVariables.NIXOS_OZONE_WL = "1";`);
  the wrappers then pass `--ozone-platform-hint=auto` when `WAYLAND_DISPLAY` is set.
* `--no-sandbox` is always passed (Chromium's setuid sandbox can't exist in the store).
* The `.desktop` file keeps upstream's `StartupWMClass=grok-bot`, MIME handlers
  `x-scheme-handler/grokbot` and `sand` (login callbacks), and `Icon=grok-bot`.
* GitHub pauses scheduled workflows after 60 days without repo activity; the
  daily bumps themselves count as activity.

## License

MIT for the packaging code in this repo (see `LICENSE`). Grok Bot is not covered by it.
