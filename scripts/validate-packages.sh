#!/usr/bin/env bash

set -euo pipefail

PACKAGES_DIR="packages"
required_json_fields=(
  pkgname
  repo
  release_strategy
  allow_prerelease
  tag_to_pkgver
  source_field
  source_template
  checksum_field
)

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

  pkgname=$(jq -r '.pkgname' "$metadata_file")
  actual_pkgname=$(sed -nE 's/^pkgname=([^[:space:]]+)$/\1/p' "$pkgbuild_file" | head -n1)
  if [ "$pkgname" != "$actual_pkgname" ]; then
    echo "pkgname mismatch in ${package_dir}: metadata=${pkgname} pkgbuild=${actual_pkgname}" >&2
    exit 1
  fi

  (
    cd "$package_dir"
    makepkg --printsrcinfo > /dev/null
  )
done

echo "Package metadata validation passed."
