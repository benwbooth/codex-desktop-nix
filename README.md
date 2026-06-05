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

OpenAI publishes `Codex.dmg` at a stable URL and overwrites it with every release. This flake tracks the DMG as a `flake = false` input, so a normal flake update bumps it:

```sh
nix flake update codex-desktop          # in the consumer flake
# or, from within this repo:
nix flake update codex-dmg
```

`flake.lock` records the new `narHash`; the next build picks up the fresh DMG automatically. No manual hash patching.

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
