#!/usr/bin/env bash

set -euo pipefail

KAZUMI_API="https://api.github.com/repos/Predidit/Kazumi/releases/latest"
CLAWX_API="https://api.github.com/repos/ValueCell-ai/ClawX/releases/latest"
ANIMEKO_API="https://api.github.com/repos/open-ani/animeko/releases?per_page=100"
ECHOMUSIC_API="https://api.github.com/repos/hoowhoami/EchoMusic/releases/latest"

KAZUMI_PKG="packages/kazumi-bin/PKGBUILD"
CLAWX_PKG="packages/clawx-bin/PKGBUILD"
ANIMEKO_PKG="packages/animeko-appimage-beta/PKGBUILD"
ECHOMUSIC_PKG="packages/echomusic-bin/PKGBUILD"

required_files=(
  "$KAZUMI_PKG"
  "$CLAWX_PKG"
  "$ANIMEKO_PKG"
  "$ECHOMUSIC_PKG"
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

set_deb_sha512() {
  local pkgfile="$1"
  local source_url="$2"
  local source_sha

  source_sha=$(download_sha512 "$source_url")
  sed -i -E "s|^sha512sums=.*|sha512sums=('${source_sha}')|" "$pkgfile"
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

update_stable_deb_package() {
  local label="$1"
  local api_url="$2"
  local pkgfile="$3"
  local source_prefix="$4"
  local source_name_template="$5"
  local strip_v="$6"
  local release_json latest_tag latest current source_name source_url

  release_json=$(curl -fsSL "$api_url")
  latest_tag=$(printf '%s' "$release_json" | jq -r '.tag_name')
  latest="$latest_tag"
  if [ "$strip_v" = "true" ]; then
    latest=${latest_tag#v}
  fi

  printf -v "${label}_latest" '%s' "$latest"
  current=$(extract_pkgver "$pkgfile")

  if [ "$(printf '%s' "$release_json" | jq -r '.prerelease')" = "true" ]; then
    printf -v "${label}_update" '%s' false
    echo "${label} latest release is prerelease (${latest_tag}), skip update"
    return
  fi

  if [ "$latest" != "$current" ]; then
    printf -v "${label}_update" '%s' true
    sed -i "s/^pkgver=.*/pkgver=${latest}/" "$pkgfile"
    printf -v source_name "$source_name_template" "$latest"
    source_url="${source_prefix}${source_name}"
    set_deb_sha512 "$pkgfile" "$source_url"
    echo "${label} update: ${current} -> ${latest}"
  else
    printf -v "${label}_update" '%s' false
    echo "${label} already latest: ${current}"
  fi
}

update_animeko_package() {
  local releases_json latest_tag latest current source_ver source_url

  releases_json=$(curl -fsSL "$ANIMEKO_API")
  latest_tag=$(printf '%s' "$releases_json" | jq -r '[.[] | select(.prerelease == true and (.tag_name | test("beta"; "i")))] | .[0].tag_name // ""')
  if [ -z "$latest_tag" ]; then
    latest_tag=$(printf '%s' "$releases_json" | jq -r '[.[] | select(.tag_name | test("beta"; "i"))] | .[0].tag_name // ""')
  fi
  if [ -z "$latest_tag" ]; then
    echo "No animeko beta tag found" >&2
    exit 1
  fi

  latest=$(normalize_animeko_pkgver "$latest_tag")
  animeko_latest="$latest"
  current=$(extract_pkgver "$ANIMEKO_PKG")

  if [ "$latest" != "$current" ]; then
    animeko_update=true
    sed -i -E "s/^pkgver=\"?.*\"?$/pkgver=\"${latest}\"/" "$ANIMEKO_PKG"
    source_ver=$(normalize_animeko_source_ver "$latest")
    source_url="https://github.com/open-ani/animeko/releases/download/v${source_ver}/ani-${source_ver}-linux-x86_64.appimage"
    sed -i -E "s|^source_x86_64=.*|source_x86_64=(\"${source_url}\")|" "$ANIMEKO_PKG"
    set_animeko_sha512 "$ANIMEKO_PKG" "$source_url"
    echo "animeko-appimage-beta update: ${current} -> ${latest}"
  else
    animeko_update=false
    echo "animeko-appimage-beta already latest: ${current}"
  fi
}

kazumi_update=false
clawx_update=false
animeko_update=false
echomusic_update=false

update_stable_deb_package \
  "kazumi" \
  "$KAZUMI_API" \
  "$KAZUMI_PKG" \
  "https://github.com/Predidit/Kazumi/releases/download/" \
  "%s/Kazumi_linux_%s_amd64.deb" \
  false

update_stable_deb_package \
  "clawx" \
  "$CLAWX_API" \
  "$CLAWX_PKG" \
  "https://github.com/ValueCell-ai/ClawX/releases/download/v" \
  "%s/ClawX-%s-linux-amd64.deb" \
  true

update_animeko_package

update_stable_deb_package \
  "echomusic" \
  "$ECHOMUSIC_API" \
  "$ECHOMUSIC_PKG" \
  "https://github.com/hoowhoami/EchoMusic/releases/download/v" \
  "%s/EchoMusic-%s-linux-amd64.deb" \
  true

any_update=false
if [ "$kazumi_update" = true ] || [ "$clawx_update" = true ] || [ "$animeko_update" = true ] || [ "$echomusic_update" = true ]; then
  any_update=true
fi

{
  echo "any_update=${any_update}"
  echo "kazumi_update=${kazumi_update}"
  echo "clawx_update=${clawx_update}"
  echo "animeko_update=${animeko_update}"
  echo "echomusic_update=${echomusic_update}"
  echo "kazumi_latest=${kazumi_latest}"
  echo "clawx_latest=${clawx_latest}"
  echo "animeko_latest=${animeko_latest}"
  echo "echomusic_latest=${echomusic_latest}"
} >> "$GITHUB_OUTPUT"
