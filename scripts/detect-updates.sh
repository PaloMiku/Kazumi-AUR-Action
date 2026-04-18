#!/usr/bin/env bash

set -euo pipefail

if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "GITHUB_OUTPUT is required" >&2
  exit 1
fi

PACKAGES_DIR="packages"
GITHUB_API="https://api.github.com/repos"
GITHUB_TOKEN_HEADER=()
CURL_RETRY_ARGS=(--retry 3 --retry-all-errors --retry-delay 2)
DRY_RUN="${DRY_RUN:-false}"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  GITHUB_TOKEN_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

log() {
  printf '[detect-updates] %s\n' "$*" >&2
}

write_output() {
  local any_update="$1"
  local packages_json="$2"
  local updates_json="$3"

  {
    echo "any_update=${any_update}"
    echo "updated_packages<<EOF"
    printf '%s\n' "$packages_json"
    echo "EOF"
    echo "updates_json<<EOF"
    printf '%s\n' "$updates_json"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
}

extract_pkgver() {
  local pkgfile="$1"
  sed -nE "s/^pkgver=\"?([^\"']+)\"?$/\1/p" "$pkgfile" | head -n1
}

download_sha512() {
  local pkgname="$1"
  local source_url="$2"
  local tmpfile

  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' RETURN
  log "Downloading release asset for ${pkgname}: ${source_url}"
  if ! curl -fsSL "${CURL_RETRY_ARGS[@]}" "${GITHUB_TOKEN_HEADER[@]}" "$source_url" -o "$tmpfile"; then
    echo "Failed to download release asset for ${pkgname}: ${source_url}" >&2
    exit 1
  fi
  sha512sum "$tmpfile" | awk '{print $1}'
  rm -f "$tmpfile"
  trap - RETURN
}

update_pkgbuild_field() {
  local pkgfile="$1"
  local field="$2"
  local value="$3"

  if [ "$DRY_RUN" = "true" ]; then
    log "DRY_RUN would set ${pkgfile}:${field}=${value}"
    return
  fi

  sed -i -E "s|^${field}=.*$|${field}=${value}|" "$pkgfile"
}

update_array_field() {
  local pkgfile="$1"
  local field="$2"
  local value="$3"

  if [ "$DRY_RUN" = "true" ]; then
    log "DRY_RUN would set ${pkgfile}:${field}=(\"${value}\")"
    return
  fi

  sed -i -E "s|^${field}=.*$|${field}=(\"${value}\")|" "$pkgfile"
}

update_checksum_field() {
  local pkgname="$1"
  local pkgfile="$2"
  local field="$3"
  local source_url="$4"
  local checksum

  checksum=$(download_sha512 "$pkgname" "$source_url")

  if [ "$DRY_RUN" = "true" ]; then
    log "DRY_RUN would set ${pkgfile}:${field}=('${checksum}')"
    return
  fi

  sed -i -E "s|^${field}=.*$|${field}=('${checksum}')|" "$pkgfile"
}

update_source_entry() {
  local pkgname="$1"
  local pkgfile="$2"
  local pkgver="$3"
  local source_tag="$4"
  local field="$5"
  local template="$6"
  local checksum_field="$7"
  local source_value source_url

  source_value=$(render_source_template "$template" "$pkgver" "$source_tag")
  source_url=${source_value##*::}
  if [ "$source_url" = "$source_value" ]; then
    source_url="$source_value"
  fi

  update_array_field "$pkgfile" "$field" "$source_value"
  update_checksum_field "$pkgname" "$pkgfile" "$checksum_field" "$source_url"
}

normalize_tag_to_pkgver() {
  local strategy="$1"
  local tag="$2"

  case "$strategy" in
    identity)
      printf '%s' "$tag"
      ;;
    strip_v)
      printf '%s' "${tag#v}"
      ;;
    animeko_beta)
      printf '%s' "${tag#v}" | sed -E 's/-?(alpha|beta)/\1/g; s/-/./g; s/\.\././g'
      ;;
    surf_beta)
      printf '%s' "$tag" | sed -E 's/-beta\./beta/g; s/-rc\./rc/g'
      ;;
    *)
      echo "Unknown tag_to_pkgver strategy: ${strategy}" >&2
      exit 1
      ;;
  esac
}

normalize_pkgver_to_tag() {
  local strategy="$1"
  local pkgver="$2"

  case "$strategy" in
    identity)
      printf '%s' "$pkgver"
      ;;
    strip_v)
      printf 'v%s' "$pkgver"
      ;;
    animeko_beta)
      printf 'v%s' "$pkgver" | sed -E 's/(alpha|beta)/-\1/g; s/-{2,}/-/g'
      ;;
    surf_beta)
      printf '%s' "$pkgver" | sed -E 's/beta/-beta./; s/rc/-rc./'
      ;;
    *)
      echo "Unknown pkgver_to_tag strategy: ${strategy}" >&2
      exit 1
      ;;
  esac
}

render_source_template() {
  local template="$1"
  local pkgver="$2"
  local tag="$3"
  local tag_no_v="${tag#v}"

  printf '%s' "$template" \
    | sed -e "s|{pkgver}|${pkgver}|g" \
          -e "s|{tag_no_v}|${tag_no_v}|g" \
          -e "s|{tag}|${tag}|g"
}

fetch_github_latest_release() {
  local repo="$1"
  curl -fsSL "${CURL_RETRY_ARGS[@]}" "${GITHUB_TOKEN_HEADER[@]}" "${GITHUB_API}/${repo}/releases/latest"
}

fetch_github_releases() {
  local repo="$1"
  curl -fsSL "${CURL_RETRY_ARGS[@]}" "${GITHUB_TOKEN_HEADER[@]}" "${GITHUB_API}/${repo}/releases?per_page=100"
}

select_release_json() {
  local strategy="$1"
  local repo="$2"
  local allow_prerelease="$3"
  local tag_pattern="$4"
  local releases_json release_json

  case "$strategy" in
    github_latest)
      if ! release_json=$(fetch_github_latest_release "$repo"); then
        echo "Failed to query latest release for ${repo}" >&2
        exit 1
      fi
      if [ "$allow_prerelease" != "true" ] && [ "$(printf '%s' "$release_json" | jq -r '.prerelease')" = "true" ]; then
        printf ''
        return
      fi
      if [ -n "$tag_pattern" ] && [ "$tag_pattern" != "null" ] && ! printf '%s' "$release_json" | jq -e --arg pattern "$tag_pattern" 'select(.tag_name | test($pattern; "i"))' >/dev/null; then
        printf ''
        return
      fi
      printf '%s' "$release_json"
      ;;
    github_beta)
      if ! releases_json=$(fetch_github_releases "$repo"); then
        echo "Failed to query releases for ${repo}" >&2
        exit 1
      fi
      if [ "$allow_prerelease" = "true" ]; then
        release_json=$(printf '%s' "$releases_json" | jq -c --arg pattern "${tag_pattern:-beta}" '[.[] | select(.prerelease == true) | select(.tag_name | test($pattern; "i"))] | .[0] // empty')
      else
        release_json=$(printf '%s' "$releases_json" | jq -c --arg pattern "${tag_pattern:-beta}" '[.[] | select(.prerelease == false) | select(.tag_name | test($pattern; "i"))] | .[0] // empty')
      fi
      printf '%s' "$release_json"
      ;;
    *)
      echo "Unknown release strategy: ${strategy}" >&2
      exit 1
      ;;
  esac
}

updated_packages=()
updated_versions=()

while IFS= read -r metadata_file; do
  package_dir=$(dirname "$metadata_file")
  pkgbuild_file="${package_dir}/PKGBUILD"

  if [ ! -f "$pkgbuild_file" ]; then
    echo "Missing PKGBUILD for ${metadata_file}" >&2
    exit 1
  fi

  pkgname=$(jq -r '.pkgname' "$metadata_file")
  repo=$(jq -r '.repo' "$metadata_file")
  release_strategy=$(jq -r '.release_strategy' "$metadata_file")
  allow_prerelease=$(jq -r '.allow_prerelease' "$metadata_file")
  tag_to_pkgver=$(jq -r '.tag_to_pkgver' "$metadata_file")
  tag_pattern=$(jq -r '.tag_pattern // empty' "$metadata_file")
  has_multi_source=$(jq -r 'has("sources")' "$metadata_file")

  log "Checking ${pkgname} against ${repo} (${release_strategy})"

  release_json=$(select_release_json "$release_strategy" "$repo" "$allow_prerelease" "$tag_pattern")
  if [ -z "$release_json" ] || [ "$release_json" = "null" ]; then
    log "No matching release found for ${pkgname}"
    continue
  fi

  latest_tag=$(printf '%s' "$release_json" | jq -r '.tag_name')
  latest_pkgver=$(normalize_tag_to_pkgver "$tag_to_pkgver" "$latest_tag")
  current_pkgver=$(extract_pkgver "$pkgbuild_file")

  if [ "$latest_pkgver" != "$current_pkgver" ]; then
    source_tag=$(normalize_pkgver_to_tag "$tag_to_pkgver" "$latest_pkgver")

    update_pkgbuild_field "$pkgbuild_file" "pkgver" "\"${latest_pkgver}\""

    if [ "$has_multi_source" = "true" ]; then
      while IFS=$'\t' read -r source_field source_template checksum_field; do
        update_source_entry "$pkgname" "$pkgbuild_file" "$latest_pkgver" "$source_tag" "$source_field" "$source_template" "$checksum_field"
      done < <(jq -r '.sources[] | [.field, .template, .checksum_field] | @tsv' "$metadata_file")
    else
      source_field=$(jq -r '.source_field' "$metadata_file")
      source_template=$(jq -r '.source_template' "$metadata_file")
      checksum_field=$(jq -r '.checksum_field' "$metadata_file")
      update_source_entry "$pkgname" "$pkgbuild_file" "$latest_pkgver" "$source_tag" "$source_field" "$source_template" "$checksum_field"
    fi

    updated_packages+=("$pkgname")
    updated_versions+=("$latest_pkgver")
    echo "${pkgname} update: ${current_pkgver} -> ${latest_pkgver}"
  else
    echo "${pkgname} already latest: ${current_pkgver}"
  fi
done < <(find "$PACKAGES_DIR" -mindepth 2 -maxdepth 2 -name package.json | sort)

if [ "${#updated_packages[@]}" -gt 0 ]; then
  any_update=true
else
  any_update=false
fi

packages_json=$(printf '%s\n' "${updated_packages[@]:-}" | jq -R . | jq -cs 'map(select(length > 0))')
updates_json=$(jq -cn --argjson pkgs "$packages_json" --argjson vers "$(printf '%s\n' "${updated_versions[@]:-}" | jq -R . | jq -cs 'map(select(length > 0))')" '
  [range(0; ($pkgs|length)) | {pkgname: $pkgs[.], latest: $vers[.], path: ("packages/" + $pkgs[.])}]
')

write_output "$any_update" "$packages_json" "$updates_json"

if [ "$DRY_RUN" = "true" ]; then
  log "DRY_RUN summary: any_update=${any_update}"
  log "DRY_RUN updated_packages=${packages_json}"
  log "DRY_RUN updates_json=${updates_json}"
fi
