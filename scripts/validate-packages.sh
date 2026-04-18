#!/usr/bin/env bash

set -euo pipefail

PACKAGES_DIR="packages"
required_json_fields=(
  pkgname
  repo
  release_strategy
  allow_prerelease
  tag_to_pkgver
)
supported_release_strategies=(
  github_latest
  github_beta
)
supported_tag_to_pkgver_strategies=(
  identity
  strip_v
  animeko_beta
  surf_beta
)

log() {
  printf '[validate-packages] %s\n' "$*"
}

pkgbuild_has_assignment() {
  local pkgbuild_file="$1"
  local field="$2"
  grep -Eq "^${field}=.*$" "$pkgbuild_file"
}

array_contains() {
  local needle="$1"
  shift
  local value

  for value in "$@"; do
    if [ "$value" = "$needle" ]; then
      return 0
    fi
  done

  return 1
}

validate_regex() {
  local pattern="$1"

  printf 'test-value\n' | jq -eR --arg pattern "$pattern" 'test($pattern; "i") | true' >/dev/null
}

if ! command -v makepkg >/dev/null 2>&1; then
  echo "makepkg is required for validation but was not found in PATH." >&2
  exit 1
fi

metadata_files=()
while IFS= read -r metadata_file; do
  metadata_files+=("$metadata_file")
done < <(find "$PACKAGES_DIR" -mindepth 2 -maxdepth 2 -name package.json | sort)

if [ "${#metadata_files[@]}" -eq 0 ]; then
  echo "No package metadata files found." >&2
  exit 1
fi

for metadata_file in "${metadata_files[@]}"; do
  package_dir=$(dirname "$metadata_file")
  pkgbuild_file="${package_dir}/PKGBUILD"

  if [ ! -f "$pkgbuild_file" ]; then
    echo "Missing PKGBUILD: ${pkgbuild_file}" >&2
    exit 1
  fi

  jq -e . "$metadata_file" >/dev/null

  for field in "${required_json_fields[@]}"; do
    if [ "$(jq -r --arg field "$field" 'has($field)' "$metadata_file")" != "true" ]; then
      echo "Missing metadata field '${field}' in ${metadata_file}" >&2
      exit 1
    fi
  done

  release_strategy=$(jq -r '.release_strategy' "$metadata_file")
  if ! array_contains "$release_strategy" "${supported_release_strategies[@]}"; then
    echo "Unsupported release_strategy '${release_strategy}' in ${metadata_file}" >&2
    exit 1
  fi

  tag_to_pkgver=$(jq -r '.tag_to_pkgver' "$metadata_file")
  if ! array_contains "$tag_to_pkgver" "${supported_tag_to_pkgver_strategies[@]}"; then
    echo "Unsupported tag_to_pkgver '${tag_to_pkgver}' in ${metadata_file}" >&2
    exit 1
  fi

  has_single_source=$(jq -r 'has("source_field") and has("source_template") and has("checksum_field")' "$metadata_file")
  has_multi_source=$(jq -r 'has("sources")' "$metadata_file")
  if [ "$has_single_source" != "true" ] && [ "$has_multi_source" != "true" ]; then
    echo "Missing source metadata in ${metadata_file}: require source_field/source_template/checksum_field or sources[]" >&2
    exit 1
  fi

  if [ "$has_multi_source" = "true" ]; then
    if ! jq -e '.sources | type == "array" and length > 0 and all(.[]; has("field") and has("template") and has("checksum_field"))' "$metadata_file" >/dev/null; then
      echo "Invalid sources[] metadata in ${metadata_file}" >&2
      exit 1
    fi

    if ! jq -e '([.sources[].field] | unique | length) == ([.sources[].field] | length)' "$metadata_file" >/dev/null; then
      echo "Duplicate source field entries in ${metadata_file}" >&2
      exit 1
    fi

    if ! jq -e '([.sources[].checksum_field] | unique | length) == ([.sources[].checksum_field] | length)' "$metadata_file" >/dev/null; then
      echo "Duplicate checksum field entries in ${metadata_file}" >&2
      exit 1
    fi

    while IFS=$'\t' read -r source_field checksum_field; do
      if ! pkgbuild_has_assignment "$pkgbuild_file" "$source_field"; then
        echo "Missing source field '${source_field}' in ${pkgbuild_file}" >&2
        exit 1
      fi

      if ! pkgbuild_has_assignment "$pkgbuild_file" "$checksum_field"; then
        echo "Missing checksum field '${checksum_field}' in ${pkgbuild_file}" >&2
        exit 1
      fi
    done < <(jq -r '.sources[] | [.field, .checksum_field] | @tsv' "$metadata_file")
  else
    source_field=$(jq -r '.source_field' "$metadata_file")
    checksum_field=$(jq -r '.checksum_field' "$metadata_file")

    if ! pkgbuild_has_assignment "$pkgbuild_file" "$source_field"; then
      echo "Missing source field '${source_field}' in ${pkgbuild_file}" >&2
      exit 1
    fi

    if ! pkgbuild_has_assignment "$pkgbuild_file" "$checksum_field"; then
      echo "Missing checksum field '${checksum_field}' in ${pkgbuild_file}" >&2
      exit 1
    fi
  fi

  pkgname=$(jq -r '.pkgname' "$metadata_file")
  package_dir_name=$(basename "$package_dir")

  if [ "$pkgname" != "$package_dir_name" ]; then
    echo "Package directory name mismatch in ${package_dir}: expected ${pkgname}" >&2
    exit 1
  fi

  actual_pkgname=$(sed -nE 's/^pkgname=([^[:space:]]+)$/\1/p' "$pkgbuild_file" | head -n1)
  if [ "$pkgname" != "$actual_pkgname" ]; then
    echo "pkgname mismatch in ${package_dir}: metadata=${pkgname} pkgbuild=${actual_pkgname}" >&2
    exit 1
  fi

  tag_pattern=$(jq -r '.tag_pattern // empty' "$metadata_file")
  if [ -n "$tag_pattern" ] && ! validate_regex "$tag_pattern"; then
    echo "Invalid tag_pattern '${tag_pattern}' in ${metadata_file}" >&2
    exit 1
  fi

  (
    cd "$package_dir"
    makepkg --printsrcinfo > /dev/null
  )

  log "Validated ${pkgname}"
done

echo "Package metadata validation passed."
