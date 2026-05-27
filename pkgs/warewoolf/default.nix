# Warewoolf — a minimalist, keyboard-driven novel writing system.
# Upstream: https://github.com/brsloan/warewoolf
#
# Packaging notes:
# - Pure JS Electron app: no bundler, no build step. The `package` /
#   `make` npm scripts invoke electron-forge to produce distributable
#   bundles; we don't need them. `dontNpmBuild = true` skips the
#   default `npm run build` (which warewoolf doesn't define anyway).
# - We reuse the system electron from nixpkgs instead of letting npm
#   download a private binary (ELECTRON_SKIP_BINARY_DOWNLOAD=1) and
#   wrap it pointing at the installed app dir.
# - The lone native dep in package-lock.json is `nan`, pulled in only
#   by macos-alias (darwin-only, optional). No node-gyp work on Linux.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  electron,
}:
buildNpmPackage (finalAttrs: {
  pname = "warewoolf";
  version = "2.2.1";

  src = fetchFromGitHub {
    owner = "brsloan";
    repo = "warewoolf";
    rev = "v${finalAttrs.version}";
    hash = "sha256-JtuqG6zwN+k7MoFP890vmhqL3w8IbH4QDaOPVTtrDqM=";
  };

  npmDepsHash = "sha256-FXE5IcwOpSkukiTjZWfduP5F+5fs4pjEiQ7vwMIbcMU=";

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];

  dontNpmBuild = true;

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
  };

  # Upstream src/index.js unconditionally calls `openDevTools()` on the
  # main window. Because we launch the unpacked tree via electron rather
  # than a packaged build, `app.isPackaged` is false and the
  # `devTools: !app.isPackaged` guard above also resolves true, so the
  # inspector pops open on every launch. Drop the auto-open call; the
  # devtools API remains reachable via the menu/keybinding.
  postPatch = ''
    substituteInPlace src/index.js \
      --replace-fail "mainWindow.webContents.openDevTools();" ""
  '';

  # buildNpmPackage's default install copies the source tree (sans dev
  # deps) into $out/lib/node_modules/warewoolf and any bin entries from
  # package.json into $out/bin. warewoolf declares no bin entries, so
  # we add the launcher ourselves.
  postInstall = ''
    install -Dm444 src/assets/icon.png \
      "$out/share/icons/hicolor/512x512/apps/warewoolf.png"

    makeWrapper ${lib.getExe electron} "$out/bin/warewoolf" \
      --add-flags "$out/lib/node_modules/warewoolf" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --inherit-argv0
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "warewoolf";
      exec = "warewoolf %F";
      icon = "warewoolf";
      desktopName = "Warewoolf";
      genericName = "Novel writing system";
      comment = "Minimalist, keyboard-driven novel writing system";
      categories = ["Office" "WordProcessor"];
      mimeTypes = ["application/x-warewoolf-project"];
      startupWMClass = "warewoolf";
    })
  ];

  meta = {
    description = "Minimalist, keyboard-driven novel writing system";
    homepage = "https://github.com/brsloan/warewoolf";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "warewoolf";
  };
})
