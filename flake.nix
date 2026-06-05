{
  description = "OpenAI Codex Desktop for Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Codex.dmg as a flake input. `nix flake update codex-dmg` re-fetches
    # and bumps the narHash in flake.lock when OpenAI ships an update.
    codex-dmg = {
      url = "file+https://persistent.oaistatic.com/codex-app-prod/Codex.dmg";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, codex-dmg }: let
    forAllSystems = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f system);

    mkPackage = system: let
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      inherit (pkgs) lib stdenv fetchurl _7zz asar nodejs_22 python3 makeWrapper
                     electron_40 gnumake pkg-config libicns;
      betterSqlite3Version = "12.9.0";
      nodePtyVersion = "1.1.0";
      betterSqlite3Src = fetchurl {
        url = "https://registry.npmjs.org/better-sqlite3/-/better-sqlite3-${betterSqlite3Version}.tgz";
        hash = "sha256-rQ4pZQFAxJ0DNbHTVllqqBZvErdY9BiphEYTDjJ48lA=";
      };
      nodePtySrc = fetchurl {
        url = "https://registry.npmjs.org/node-pty/-/node-pty-${nodePtyVersion}.tgz";
        hash = "sha256-x1F/GQg93LBfJ2kEaA6ysRprXsq3eLjk5WhabWRbP2A=";
      };
    in stdenv.mkDerivation {
      pname = "codex-desktop";
      version = "unstable";

      src = codex-dmg;

      nativeBuildInputs = [
        _7zz asar nodejs_22 python3 makeWrapper electron_40 gnumake pkg-config libicns
      ];
      buildInputs = [ nodejs_22 python3 ];

      unpackPhase = ''
        mkdir -p dmg-extract
        ${_7zz}/bin/7zz x -y "$src" -o"dmg-extract" 2>&1
        APP_PATH=$(find dmg-extract -name "Codex.app" -type d | head -1)
        [ -z "$APP_PATH" ] && { echo "Could not find Codex.app in DMG"; find dmg-extract -type d; exit 1; }
        cp -r "$APP_PATH" ./Codex.app
        rm -rf dmg-extract
      '';

      patchPhase = ''
        RESOURCES_DIR="./Codex.app/Contents/Resources"
        [ -f "$RESOURCES_DIR/app.asar" ] || { echo "app.asar not found"; exit 1; }

        ${asar}/bin/asar extract "$RESOURCES_DIR/app.asar" app-extracted
        if [ -d "$RESOURCES_DIR/app.asar.unpacked" ]; then
          cp -r "$RESOURCES_DIR/app.asar.unpacked/"* app-extracted/ 2>/dev/null || true
        fi

        rm -rf app-extracted/node_modules/sparkle-darwin 2>/dev/null || true
        find app-extracted -name "sparkle.node" -delete 2>/dev/null || true

        # Pinned native-module versions must match what the DMG bundles.
        appBetterSqlite3=$(${nodejs_22}/bin/node -p "require('./app-extracted/node_modules/better-sqlite3/package.json').version")
        appNodePty=$(${nodejs_22}/bin/node -p "require('./app-extracted/node_modules/node-pty/package.json').version")
        [ "$appBetterSqlite3" = "${betterSqlite3Version}" ] || { echo "better-sqlite3 mismatch: app has $appBetterSqlite3, pinned ${betterSqlite3Version}"; exit 1; }
        [ "$appNodePty" = "${nodePtyVersion}" ] || { echo "node-pty mismatch: app has $appNodePty, pinned ${nodePtyVersion}"; exit 1; }

        # Drop macOS-compiled .node binaries; rebuilt for Linux Electron below.
        find app-extracted -name "*.node" -delete 2>/dev/null || true
      '';

      configurePhase = ''
        export HOME=$TMPDIR
      '';

      buildPhase = ''
        cd app-extracted
        export npm_config_target=${electron_40.version}
        export npm_config_runtime=electron
        export npm_config_nodedir=${electron_40.headers}
        export HOME=$TMPDIR

        build_native_module() {
          local module_name="$1" module_tarball="$2"
          rm -rf "node_modules/$module_name"
          mkdir -p "node_modules/$module_name"
          tar -xzf "$module_tarball" --strip-components=1 -C "node_modules/$module_name"
          cd "node_modules/$module_name"
          ${nodejs_22}/bin/node ${nodejs_22}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js rebuild --release
          cd ../..
        }

        build_native_module better-sqlite3 ${betterSqlite3Src}
        build_native_module node-pty ${nodePtySrc}

        cd ..
        ${asar}/bin/asar pack app-extracted repacked.asar --unpack "**/*.{node,so,dylib}"
      '';

      installPhase = ''
        mkdir -p $out/lib/codex-desktop/resources $out/bin $out/share/applications

        # Extract app icon from .icns into hicolor sizes
        if [ -f ./Codex.app/Contents/Resources/app.icns ]; then
          icnsDir=$(mktemp -d)
          ${libicns}/bin/icns2png -x -o "$icnsDir" ./Codex.app/Contents/Resources/app.icns
          for size in 32 64 128 256 512 1024; do
            png="$icnsDir/app_''${size}x''${size}x32.png"
            [ -f "$png" ] || continue
            install -Dm0644 "$png" "$out/share/icons/hicolor/''${size}x''${size}/apps/codex-desktop.png"
          done
        fi

        # Linux Electron runtime
        cp ${electron_40}/libexec/electron/electron $out/lib/codex-desktop/
        for f in ${electron_40}/libexec/electron/*.pak ${electron_40}/libexec/electron/*.dat \
                 ${electron_40}/libexec/electron/v8_context_snapshot*.bin \
                 ${electron_40}/libexec/electron/snapshot_blob*.bin; do
          [ -e "$f" ] && cp "$f" $out/lib/codex-desktop/
        done
        [ -d "${electron_40}/libexec/electron/locales" ] && cp -r "${electron_40}/libexec/electron/locales" $out/lib/codex-desktop/
        [ -f "${electron_40}/libexec/electron/chrome_crashpad_handler" ] && cp "${electron_40}/libexec/electron/chrome_crashpad_handler" $out/lib/codex-desktop/
        for bin in ${electron_40}/libexec/electron/chrome_*.so \
                   ${electron_40}/libexec/electron/libEGL*.so* \
                   ${electron_40}/libexec/electron/libGLES*.so* \
                   ${electron_40}/libexec/electron/libffmpeg*.so* \
                   ${electron_40}/libexec/electron/libvk_swiftshader*.so* \
                   ${electron_40}/libexec/electron/libvulkan*.so*; do
          [ -e "$bin" ] && cp "$bin" $out/lib/codex-desktop/ 2>/dev/null || true
        done

        # Patched app + rebuilt native modules
        cp repacked.asar $out/lib/codex-desktop/resources/app.asar
        [ -d repacked.asar.unpacked ] && cp -r repacked.asar.unpacked $out/lib/codex-desktop/resources/app.asar.unpacked
        if [ -f app-extracted/node_modules/better-sqlite3/build/Release/better_sqlite3.node ]; then
          mkdir -p $out/lib/codex-desktop/resources/app.asar.unpacked/node_modules/better-sqlite3/build/Release
          cp app-extracted/node_modules/better-sqlite3/build/Release/better_sqlite3.node \
            $out/lib/codex-desktop/resources/app.asar.unpacked/node_modules/better-sqlite3/build/Release/
        fi
        if [ -d app-extracted/node_modules/node-pty/build/Release ]; then
          mkdir -p $out/lib/codex-desktop/resources/app.asar.unpacked/node_modules/node-pty/build/Release
          cp -r app-extracted/node_modules/node-pty/build/Release/* \
            $out/lib/codex-desktop/resources/app.asar.unpacked/node_modules/node-pty/build/Release/
        fi
        if [ -d "app-extracted/webview" ]; then
          mkdir -p $out/lib/codex-desktop/content/webview
          cp -r app-extracted/webview/* $out/lib/codex-desktop/content/webview/
        fi

        # Launcher
        cat > $out/bin/codex-desktop << 'WRAPPER'
#!/bin/bash
export LD_LIBRARY_PATH="${electron_40}/lib:${electron_40}/libexec/electron''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# Force X11/XWayland: native Wayland triggers hover-state ghosting and
# wrong-pane-width layout bugs in this app. Override with CODEX_OZONE=wayland.
export ELECTRON_OZONE_PLATFORM_HINT="''${CODEX_OZONE:-x11}"
unset NIXOS_OZONE_WL
export ZELLIJ=''${ZELLIJ:-0}

APPDIR="$(dirname "$(dirname "$(readlink -f "$0")")")"
WEBVIEW_DIR="$APPDIR/lib/codex-desktop/content/webview"

if [ -d "$WEBVIEW_DIR" ] && [ -n "$(ls -A "$WEBVIEW_DIR" 2>/dev/null)" ]; then
  cd "$WEBVIEW_DIR"
  if ${python3}/bin/python3 -c \
      "import socket; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,0); s.bind(('127.0.0.1',5175)); s.close()" \
      2>/dev/null; then
    ${python3}/bin/python3 -m http.server 5175 --bind 127.0.0.1 > /dev/null 2>&1 &
    HTTP_PID=$!
    trap "kill $HTTP_PID 2>/dev/null" EXIT
  fi
fi

if [ -z "''${CODEX_CLI_PATH:-}" ] && command -v codex >/dev/null 2>&1; then
  export CODEX_CLI_PATH="$(command -v codex)"
fi

cd "$APPDIR/lib/codex-desktop"
if [ -z "''${CODEX_ENABLE_SANDBOX:-}" ]; then
  exec "$APPDIR/lib/codex-desktop/electron" --no-sandbox "--ozone-platform=$ELECTRON_OZONE_PLATFORM_HINT" resources/app.asar "$@"
else
  exec "$APPDIR/lib/codex-desktop/electron" "--ozone-platform=$ELECTRON_OZONE_PLATFORM_HINT" resources/app.asar "$@"
fi
WRAPPER
        chmod +x $out/bin/codex-desktop

        cat > $out/share/applications/codex-desktop.desktop <<EOF
[Desktop Entry]
Name=Codex Desktop
Exec=codex-desktop
Icon=codex-desktop
Type=Application
Categories=Development;IDE;
StartupWMClass=Codex
Comment=OpenAI Codex Desktop
EOF
      '';

      dontStrip = true;
      dontPatchELF = true;

      meta = {
        description = "OpenAI Codex Desktop for Linux";
        homepage = "https://github.com/benwbooth/codex-desktop-nix";
        # Packaging recipe adapted from y0usaf/codex-desktop-flake (MIT).
        # Codex Desktop itself is proprietary OpenAI software.
        license = lib.licenses.mit;
        platforms = [ "x86_64-linux" "aarch64-linux" ];
      };
    };
  in {
    packages = forAllSystems (system: {
      default = mkPackage system;
      codex-desktop = mkPackage system;
    });

    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = "${mkPackage system}/bin/codex-desktop";
      };
    });
  };
}
