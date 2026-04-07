#!/usr/bin/env bash

set -euo pipefail

KAZUMI_API="https://api.github.com/repos/Predidit/Kazumi/releases/latest"
CLAWX_API="https://api.github.com/repos/ValueCell-ai/ClawX/releases/latest"
ANIMEKO_API="https://api.github.com/repos/open-ani/animeko/releases?per_page=100"

KAZUMI_PKG="packages/kazumi-bin/PKGBUILD"
CLAWX_PKG="packages/clawx-bin/PKGBUILD"
ANIMEKO_PKG="packages/animeko-appimage-beta/PKGBUILD"

required_files=(
  "$KAZUMI_PKG"
  "$CLAWX_PKG"
  "$ANIMEKO_PKG"
)

for file in "${required_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "Missing PKGBUILD: $file" >&2
    exit 1
  fi
done

if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "GITHUB_OUTPUT is required" >&2
  exit 1
fi

extract_pkgver() {
  local pkgfile="$1"
  sed -nE "s/^pkgver=\"?([^\"']+)\"?$/\1/p" "$pkgfile" | head -n1
}

normalize_animeko_pkgver() {
  local tag="$1"
  printf '%s' "${tag#v}" | sed -E 's/-?(alpha|beta)/\1/g; s/-/./g; s/\.\././g'
}

normalize_animeko_source_ver() {
  local pkgver="$1"
  printf '%s' "$pkgver" | sed -E 's/(alpha|beta)/-\1/g; s/-{2,}/-/g'
}

set_animeko_sha512() {
  local pkgfile="$1"
  local source_url="$2"
  local sha

  sha=$(download_sha512 "$source_url")
  sed -i -E "s|^sha512sums_x86_64=.*|sha512sums_x86_64=('${sha}')|" "$pkgfile"
}

download_sha512() {
  local source_url="$1"
  local tmpfile

  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' RETURN

  curl -fsSL "$source_url" -o "$tmpfile"
  sha512sum "$tmpfile" | awk '{print $1}'

  rm -f "$tmpfile"
  trap - RETURN
}

set_kazumi_sha512s() {
  local pkgfile="$1"
  local version="$2"
  local source_url
  local source_sha

  source_url="https://github.com/Predidit/Kazumi/releases/download/${version}/Kazumi_linux_${version}_amd64.deb"
  source_sha=$(download_sha512 "$source_url")

  sed -i -E "s|^sha512sums=.*|sha512sums=('${source_sha}')|" "$pkgfile"
}

set_clawx_sha512() {
  local pkgfile="$1"
  local version="$2"
  local source_url
  local source_sha

  source_url="https://github.com/ValueCell-ai/ClawX/releases/download/v${version}/ClawX-${version}-linux-amd64.deb"
  source_sha=$(download_sha512 "$source_url")

  sed -i -E "s|^sha512sums=.*|sha512sums=('${source_sha}')|" "$pkgfile"
}

kazumi_latest=$(curl -fsSL "$KAZUMI_API" | jq -r '.tag_name')
kazumi_current=$(extract_pkgver "$KAZUMI_PKG")

clawx_release_json=$(curl -fsSL "$CLAWX_API")
clawx_prerelease=$(printf '%s' "$clawx_release_json" | jq -r '.prerelease')
clawx_latest_tag=$(printf '%s' "$clawx_release_json" | jq -r '.tag_name')
clawx_latest=${clawx_latest_tag#v}
clawx_current=$(extract_pkgver "$CLAWX_PKG")

animeko_releases_json=$(curl -fsSL "$ANIMEKO_API")
animeko_latest_tag=$(printf '%s' "$animeko_releases_json" | jq -r '[.[] | select(.prerelease == true and (.tag_name | test("beta"; "i")))] | .[0].tag_name // ""')
if [ -z "$animeko_latest_tag" ]; then
  animeko_latest_tag=$(printf '%s' "$animeko_releases_json" | jq -r '[.[] | select(.tag_name | test("beta"; "i"))] | .[0].tag_name // ""')
fi
if [ -z "$animeko_latest_tag" ]; then
  echo "No animeko beta tag found" >&2
  exit 1
fi

animeko_latest=$(normalize_animeko_pkgver "$animeko_latest_tag")
animeko_current=$(extract_pkgver "$ANIMEKO_PKG")

kazumi_update=false
clawx_update=false
animeko_update=false

if [ "$kazumi_latest" != "$kazumi_current" ]; then
  kazumi_update=true
  sed -i "s/^pkgver=.*/pkgver=${kazumi_latest}/" "$KAZUMI_PKG"
  set_kazumi_sha512s "$KAZUMI_PKG" "$kazumi_latest"
  echo "kazumi-bin update: ${kazumi_current} -> ${kazumi_latest}"
else
  echo "kazumi-bin already latest: ${kazumi_current}"
fi

if [ "$clawx_prerelease" = "true" ]; then
  echo "clawx latest release is prerelease (${clawx_latest_tag}), skip update"
elif [ "$clawx_latest" != "$clawx_current" ]; then
  clawx_update=true
  sed -i "s/^pkgver=.*/pkgver=${clawx_latest}/" "$CLAWX_PKG"
  set_clawx_sha512 "$CLAWX_PKG" "$clawx_latest"
  echo "clawx-bin update: ${clawx_current} -> ${clawx_latest}"
else
  echo "clawx-bin already latest: ${clawx_current}"
fi

if [ "$animeko_latest" != "$animeko_current" ]; then
  animeko_update=true
  sed -i -E "s/^pkgver=\"?.*\"?$/pkgver=\"${animeko_latest}\"/" "$ANIMEKO_PKG"

  animeko_source_ver=$(normalize_animeko_source_ver "$animeko_latest")
  animeko_source_url="https://github.com/open-ani/animeko/releases/download/v${animeko_source_ver}/ani-${animeko_source_ver}-linux-x86_64.appimage"
  sed -i -E "s|^source_x86_64=.*|source_x86_64=(\"${animeko_source_url}\")|" "$ANIMEKO_PKG"

  set_animeko_sha512 "$ANIMEKO_PKG" "$animeko_source_url"
  echo "animeko-appimage-beta update: ${animeko_current} -> ${animeko_latest}"
else
  echo "animeko-appimage-beta already latest: ${animeko_current}"
fi

any_update=false
if [ "$kazumi_update" = true ] || [ "$clawx_update" = true ] || [ "$animeko_update" = true ]; then
  any_update=true
fi

{
  echo "any_update=${any_update}"
  echo "kazumi_update=${kazumi_update}"
  echo "clawx_update=${clawx_update}"
  echo "animeko_update=${animeko_update}"
  echo "kazumi_latest=${kazumi_latest}"
  echo "clawx_latest=${clawx_latest}"
  echo "animeko_latest=${animeko_latest}"
} >> "$GITHUB_OUTPUT"
