#!/usr/bin/env bash

set -euo pipefail

if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "GITHUB_OUTPUT is required" >&2
  exit 1
fi

PACKAGES_DIR="packages"

input_packages="${INPUT_PACKAGES:-}"

new_packages=()

if [ -n "$input_packages" ]; then
  IFS=',' read -ra input_array <<< "$input_packages"
  for pkg in "${input_array[@]}"; do
    pkg=$(echo "$pkg" | xargs)
    if [ -d "${PACKAGES_DIR}/${pkg}" ]; then
      new_packages+=("$pkg")
    fi
  done
else
  while IFS= read -r pkgname; do
    if [ -d "${PACKAGES_DIR}/${pkgname}" ]; then
      new_packages+=("$pkgname")
    fi
  done < <(find "$PACKAGES_DIR" -mindepth 2 -maxdepth 2 -name package.json -exec dirname {} \; | xargs -I{} basename {} | sort)
fi

if [ ${#new_packages[@]} -eq 0 ]; then
  echo "new_packages=[]" >> "$GITHUB_OUTPUT"
  echo "new_packages_json=[]" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Detected new packages: ${new_packages[*]}"

packages_json=$(printf '%s\n' "${new_packages[@]}" | jq -R . | jq -cs 'map(select(length > 0))')

new_packages_json=$(jq -cn --argjson pkgs "$packages_json" '
  [range(0; ($pkgs|length)) | {pkgname: $pkgs[.], path: ("packages/" + $pkgs[.])}]
')

echo "new_packages=${new_packages[*]}" >> "$GITHUB_OUTPUT"
echo "new_packages_json<<EOF" >> "$GITHUB_OUTPUT"
printf '%s\n' "$new_packages_json" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"