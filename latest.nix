# "Always latest at launch" variant.
#
# `grok-bot-latest` does NOT contain Grok Bot. On each launch it asks Cursor's
# release feed which version is current, downloads that AppImage to
# ~/.cache/grok-bot/<version>/ (once), extracts it there and runs it inside the
# same kind of FHS environment `appimageTools.wrapType2` uses. So it keeps
# working with the newest release even when this repo's pin is stale.
# Trade-off: no hash verification (the feed publishes none; HTTPS only) and a
# network request at launch (falls back to the newest cached version offline).
{
  lib,
  stdenv,
  appimageTools,
  buildFHSEnv,
  writeShellScript,
  makeWrapper,
  runCommandLocal,
  curl,
  jq,
  coreutils,
  gnugrep,
  gnused,
  grok-bot, # the pinned package; only used for its icons
}:

let
  runScript = writeShellScript "grok-bot-latest-run" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ curl jq coreutils gnugrep gnused ]}:$PATH

    case "$(uname -m)" in
      x86_64)          platform=linux-x64 ;;
      aarch64|arm64)   platform=linux-arm64 ;;
      *) echo "grok-bot-latest: unsupported architecture $(uname -m)" >&2; exit 1 ;;
    esac

    cache="''${GROK_BOT_CACHE_DIR:-''${XDG_CACHE_HOME:-$HOME/.cache}/grok-bot}"
    feed="''${GROK_BOT_FEED_URL:-https://api2.cursor.sh/updates/api/download/stable/$platform/sand}"
    mkdir -p "$cache"

    version=""; url=""
    if json=$(curl -fsSL --max-time 15 --retry 2 "$feed" 2>/dev/null); then
      version=$(jq -r '.version // empty' <<<"$json")
      url=$(jq -r '.downloadUrl // empty' <<<"$json")
    fi

    if [ -z "$version" ] || [ -z "$url" ]; then
      # Offline / feed down: use the newest cached version, if any.
      version=$(ls -1 "$cache" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -n1 || true)
      if [ -z "$version" ] || [ ! -x "$cache/$version/squashfs-root/AppRun" ]; then
        echo "grok-bot-latest: cannot reach the release feed and nothing is cached." >&2
        exit 1
      fi
      echo "grok-bot-latest: feed unreachable, using cached $version" >&2
    fi

    dir="$cache/$version"
    if [ ! -x "$dir/squashfs-root/AppRun" ]; then
      echo "grok-bot-latest: fetching Grok Bot $version ..." >&2
      tmp=$(mktemp -d "$cache/.tmp.XXXXXX")
      trap 'rm -rf "$tmp"' EXIT
      curl -fSL --retry 3 -o "$tmp/Grok_Bot.AppImage" "$url"
      chmod +x "$tmp/Grok_Bot.AppImage"
      ( cd "$tmp" && APPIMAGE_EXTRACT_AND_RUN=1 ./Grok_Bot.AppImage --appimage-extract >/dev/null )
      rm -f "$tmp/Grok_Bot.AppImage"
      rm -rf "$dir"; mkdir -p "$dir"
      mv "$tmp/squashfs-root" "$dir/squashfs-root"
      rm -rf "$tmp"; trap - EXIT
      # keep the current and one previous version
      ls -1 "$cache" | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | head -n -2 | while read -r old; do
        rm -rf "''${cache:?}/$old"
      done
    fi

    export APPDIR="$dir/squashfs-root"
    exec "$APPDIR/AppRun" "$@"
  '';

  fhs = buildFHSEnv (
    appimageTools.defaultFhsEnvArgs
    // {
      pname = "grok-bot-latest";
      version = "live";
      targetPkgs = pkgs: appimageTools.defaultFhsEnvArgs.targetPkgs pkgs ++ [ curl jq ];
      runScript = "${runScript}";
    }
  );
in
runCommandLocal "grok-bot-latest"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "Grok Bot launcher that always fetches and runs the newest release (unofficial)";
      homepage = "https://cursor.com/docs/grok-bot/deployment";
      license = lib.licenses.unfree;
      mainProgram = "grok-bot-latest";
      platforms = [ "x86_64-linux" "aarch64-linux" ];
    };
  }
  ''
    mkdir -p $out/bin $out/share/applications
    makeWrapper ${fhs}/bin/grok-bot-latest $out/bin/grok-bot-latest \
      --set-default SAND_DISABLE_UPDATES 1 \
      --add-flags "--no-sandbox" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"

    cat > $out/share/applications/grok-bot-latest.desktop <<EOF
    [Desktop Entry]
    Name=Grok Bot (latest)
    Comment=Grok Bot desktop agent - always runs the newest release
    Exec=grok-bot-latest %U
    Terminal=false
    Type=Application
    Icon=grok-bot-latest
    StartupWMClass=grok-bot
    Categories=Development;
    EOF

    # Same icons as the pinned package, renamed so both can be installed together.
    for f in $(cd ${grok-bot}/share/icons && find hicolor -name 'grok-bot.png'); do
      install -Dm444 ${grok-bot}/share/icons/$f $out/share/icons/''${f%grok-bot.png}grok-bot-latest.png
    done
  ''
