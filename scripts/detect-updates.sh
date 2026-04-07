#!/usr/bin/env bash

set -euo pipefail

KAZUMI_API="https://api.github.com/repos/Predidit/Kazumi/releases/latest"
CLAWX_API="https://api.github.com/repos/ValueCell-ai/ClawX/releases/latest"

KAZUMI_PKG="packages/kazumi-bin/PKGBUILD"
CLAWX_PKG="packages/clawx-bin/PKGBUILD"

if [ ! -f "$KAZUMI_PKG" ]; then
  echo "Missing PKGBUILD: $KAZUMI_PKG" >&2
  exit 1
fi

if [ ! -f "$CLAWX_PKG" ]; then
  echo "Missing PKGBUILD: $CLAWX_PKG" >&2
  exit 1
fi

if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "GITHUB_OUTPUT is required" >&2
  exit 1
fi

aur_exists() {
  local name="$1"
  local count

  count=$(curl -fsSL "https://aur.archlinux.org/rpc/v5/info/${name}" | jq -r '.resultcount')
  [ "$count" != "0" ]
}

kazumi_latest=$(curl -fsSL "$KAZUMI_API" | jq -r '.tag_name')
kazumi_current=$(grep -oP '^pkgver=\K.*' "$KAZUMI_PKG")

clawx_release_json=$(curl -fsSL "$CLAWX_API")
clawx_prerelease=$(printf '%s' "$clawx_release_json" | jq -r '.prerelease')
clawx_latest_tag=$(printf '%s' "$clawx_release_json" | jq -r '.tag_name')
clawx_latest=${clawx_latest_tag#v}
clawx_current=$(grep -oP '^pkgver=\K.*' "$CLAWX_PKG")

kazumi_update=false
clawx_update=false

if [ "$kazumi_latest" != "$kazumi_current" ]; then
  kazumi_update=true
  sed -i "s/^pkgver=.*/pkgver=${kazumi_latest}/" "$KAZUMI_PKG"
  echo "kazumi-bin update: ${kazumi_current} -> ${kazumi_latest}"
else
  echo "kazumi-bin already latest: ${kazumi_current}"
fi

if [ "$clawx_prerelease" = "true" ]; then
  echo "clawx latest release is prerelease (${clawx_latest_tag}), skip update"
elif [ "$clawx_latest" != "$clawx_current" ]; then
  clawx_update=true
  sed -i "s/^pkgver=.*/pkgver=${clawx_latest}/" "$CLAWX_PKG"
  echo "clawx-bin update: ${clawx_current} -> ${clawx_latest}"
else
  echo "clawx-bin already latest: ${clawx_current}"
fi

any_update=false
if [ "$kazumi_update" = true ] || [ "$clawx_update" = true ]; then
  any_update=true
fi

kazumi_aur_exists=true
clawx_aur_exists=true

if ! aur_exists "kazumi-bin"; then
  kazumi_aur_exists=false
  echo "Warning: AUR package kazumi-bin does not exist, skip deploy"
fi

if ! aur_exists "clawx-bin"; then
  clawx_aur_exists=false
  echo "Warning: AUR package clawx-bin does not exist, skip deploy"
fi

{
  echo "any_update=${any_update}"
  echo "kazumi_update=${kazumi_update}"
  echo "clawx_update=${clawx_update}"
  echo "kazumi_latest=${kazumi_latest}"
  echo "clawx_latest=${clawx_latest}"
  echo "kazumi_aur_exists=${kazumi_aur_exists}"
  echo "clawx_aur_exists=${clawx_aur_exists}"
} >> "$GITHUB_OUTPUT"
