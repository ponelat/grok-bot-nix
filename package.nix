# Grok Bot (unofficial Nix packaging of the official Linux AppImage).
# Shared by default.nix (old-style, flake-less) and flake.nix.
{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  makeWrapper,
}:

let
  pin = lib.importJSON ./version.json;
  system = stdenv.hostPlatform.system;
  # Platforms with a non-empty hash in version.json
  supported = lib.filter (s: (pin.systems.${s}.hash or "") != "") (lib.attrNames pin.systems);
  entry = pin.systems.${system} or pin.systems.x86_64-linux;

  pname = "grok-bot";
  version = pin.version;

  src = fetchurl {
    inherit (entry) url hash;
    # Name the store path nicely; the file is downloaded from Cursor's CDN at build time.
    name = "Grok_Bot_${version}.AppImage";
  };

  # Used only to pull the .desktop file and icons out of the AppImage.
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    # --- desktop entry -------------------------------------------------
    install -Dm444 ${contents}/grok-bot.desktop $out/share/applications/grok-bot.desktop
    # The upstream file says `Exec=AppRun --no-sandbox %U`; point it at our wrapper.
    substituteInPlace $out/share/applications/grok-bot.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=grok-bot %U'
    # (Icon=grok-bot and StartupWMClass=grok-bot are already correct upstream.)

    # --- icons (hicolor theme, 16..512 px) -------------------------------
    mkdir -p $out/share/icons
    cp -r ${contents}/usr/share/icons/hicolor $out/share/icons/

    # --- wrapper flags / env ---------------------------------------------
    # * --no-sandbox: chrome-sandbox can't be setuid inside the nix store / FHS env.
    # * Wayland: only when NIXOS_OZONE_WL=1 is set and a Wayland session is running.
    # * SAND_DISABLE_UPDATES=1: the in-app updater can't replace a read-only store
    #   path. Update through this repo instead. Override with
    #   `SAND_DISABLE_UPDATES=0 grok-bot` if you really want to try.
    wrapProgram $out/bin/grok-bot \
      --set-default SAND_DISABLE_UPDATES 1 \
      --add-flags "--no-sandbox" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"
  '';

  passthru = {
    inherit contents;
    updateScript = ./update.sh;
  };

  meta = {
    description = "Grok Bot desktop agent (unofficial Nix packaging of the official AppImage)";
    homepage = "https://cursor.com/docs/grok-bot/deployment";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "grok-bot";
    platforms = supported;
  };
}
