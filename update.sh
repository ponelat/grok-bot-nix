#!/usr/bin/env bash
# Rewrites version.json from Cursor's live release feed.
# Needs: curl, jq, and nix (nix-prefetch-url + nix-hash).  Usage: ./update.sh [--check]
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

FEED=https://api2.cursor.sh/updates/api/download/stable
# nix system -> feed platform
declare -A PLATFORMS=( [x86_64-linux]=linux-x64 [aarch64-linux]=linux-arm64 )

check_only=0; [ "${1:-}" = "--check" ] && check_only=1

new=$(jq -n '{systems: {}}')
version=""
for system in "${!PLATFORMS[@]}"; do
  json=$(curl -fsSL --retry 3 "$FEED/${PLATFORMS[$system]}/sand")
  v=$(jq -er .version <<<"$json")
  url=$(jq -er .downloadUrl <<<"$json")
  commit=$(jq -er .commitSha <<<"$json")
  [ -z "$version" ] && version=$v
  if [ "$v" != "$version" ]; then
    echo "feed versions differ between platforms ($version vs $v); aborting" >&2; exit 1
  fi
  old_url=$(jq -r --arg s "$system" '.systems[$s].url // ""' version.json 2>/dev/null || true)
  old_hash=$(jq -r --arg s "$system" '.systems[$s].hash // ""' version.json 2>/dev/null || true)
  if [ "$old_url" = "$url" ] && [ -n "$old_hash" ]; then
    hash=$(jq -r --arg s "$system" '.systems[$s].hash' version.json)
  else
    [ $check_only = 1 ] && { echo "update available: $version"; exit 10; }
    echo "prefetching $url" >&2
    sha=$(nix-prefetch-url --type sha256 "$url")
    hash=$(nix-hash --type sha256 --to-sri "$sha")
  fi
  new=$(jq --arg s "$system" --arg u "$url" --arg h "$hash" --arg c "$commit" \
        '.systems[$s] = {url: $u, hash: $h, commit: $c}' <<<"$new")
done

new=$(jq --arg v "$version" '. + {version: $v}' <<<"$new")
[ $check_only = 1 ] && { echo "up to date: $version"; exit 0; }
jq -S . <<<"$new" > version.json.tmp && mv version.json.tmp version.json
echo "version.json now pins $version"
