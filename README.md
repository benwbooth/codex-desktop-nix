# codex-desktop-nix

[OpenAI Codex Desktop](https://developers.openai.com/codex/app) packaged for Linux as a Nix flake.

OpenAI ships Codex Desktop for macOS and Windows; Linux is "planned". This flake repackages the upstream macOS DMG to run on Linux Electron — DMG extracted, native node modules rebuilt, app icon extracted into hicolor sizes, `.desktop` file generated, X11/XWayland forced (native Wayland has hover/sizing bugs).

## Usage

### Run once

```sh
nix run github:benwbooth/codex-desktop-nix
```

### Install into a NixOS flake

```nix
{
  inputs.codex-desktop.url = "github:benwbooth/codex-desktop-nix";

  outputs = { self, nixpkgs, codex-desktop, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            codex-desktop.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        })
      ];
    };
  };
}
```

## Keeping it current

OpenAI publishes `Codex.dmg` at a stable URL and overwrites it with every release. This flake tracks the DMG as a `flake = false` input named `codex-dmg`, so the hash lives in `flake.lock` and a flake update re-fetches.

**Inside this repo** (gets the latest DMG and commits a new lock):

```sh
cd codex-desktop-nix
nix flake update codex-dmg
git commit -am "Bump Codex.dmg"
git push
```

**In a consumer flake** — important: `nix flake update codex-desktop` here only pulls this repo's latest commit; it uses **this repo's `flake.lock`** for the DMG hash. So if upstream has shipped a new DMG but this repo hasn't been bumped yet, you stay on the old one. Two ways around that:

#### Recommended: lift `codex-dmg` to a top-level input via `follows`

```nix
inputs.codex-desktop = {
  url = "github:benwbooth/codex-desktop-nix";
  inputs.codex-dmg.follows = "codex-dmg";   # override the transitive input
};
inputs.codex-dmg = {
  url = "file+https://persistent.oaistatic.com/codex-app-prod/Codex.dmg";
  flake = false;
};
```

Now your consumer flake owns the `codex-dmg` lock at the top level. `nix flake update codex-dmg` (or a bare `nix flake update`) re-fetches OpenAI's URL directly and bumps the hash — no round-trip through this repo, no waiting for someone to push a lock bump.

#### Or, accept the indirection

If you don't add the override, your consumer is pinned to whatever this repo's `flake.lock` recorded at the commit you're on. Run `nix flake update codex-desktop` to pull the newest commit + lock from this repo when you want the latest.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `CODEX_OZONE` | `x11` | Pass `wayland` to use native Wayland (has known hover/sizing bugs with this app). |
| `CODEX_ENABLE_SANDBOX` | unset | If set, removes `--no-sandbox` (only useful on distros with a SUID Chromium sandbox helper). |
| `CODEX_CLI_PATH` | auto-detected | Path to `codex` CLI; auto-detected from `PATH` if not set. |

## Credits

Packaging structure adapted from [`y0usaf/Codex-Desktop-Flake`](https://github.com/y0usaf/Codex-Desktop-Flake) (MIT). Codex Desktop itself is proprietary OpenAI software.

## License

MIT (packaging recipe only).
