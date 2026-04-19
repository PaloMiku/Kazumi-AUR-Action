#!/usr/bin/env bash

set -euo pipefail

if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "GITHUB_OUTPUT is required" >&2
  exit 1
fi

PACKAGES_DIR="packages"

input_packages="${INPUT_PACKAGES:-}"

aur_package_exists() {
  local pkgname="$1"
  git ls-remote --exit-code "https://aur.archlinux.org/${pkgname}.git" HEAD >/dev/null 2>&1
}

write_outputs() {
  local has_new_packages="$1"
  local packages_json="$2"
  local new_packages_json="$3"

  {
    echo "has_new_packages=${has_new_packages}"
    echo "packages_json<<EOF"
    printf '%s\n' "$packages_json"
    echo "EOF"
    echo "new_packages_json<<EOF"
    printf '%s\n' "$new_packages_json"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
}

candidate_packages=()
new_packages=()

if [ -n "$input_packages" ]; then
  IFS=',' read -ra input_array <<< "$input_packages"
  for pkg in "${input_array[@]}"; do
    pkg=$(echo "$pkg" | xargs)
    if [ -d "${PACKAGES_DIR}/${pkg}" ]; then
      candidate_packages+=("$pkg")
    fi
  done
else
  while IFS= read -r pkgname; do
    if [ -d "${PACKAGES_DIR}/${pkgname}" ]; then
      candidate_packages+=("$pkgname")
    fi
  done < <(find "$PACKAGES_DIR" -mindepth 2 -maxdepth 2 -name package.json -exec dirname {} \; | xargs -I{} basename {} | sort)
fi

for pkgname in "${candidate_packages[@]}"; do
  if aur_package_exists "$pkgname"; then
    echo "Skipping existing AUR package: ${pkgname}"
    continue
  fi

  new_packages+=("$pkgname")
done

if [ ${#new_packages[@]} -eq 0 ]; then
  write_outputs false '[]' '[]'
  exit 0
fi

echo "Detected new packages: ${new_packages[*]}"

packages_json=$(jq -cn '$ARGS.positional' --args "${new_packages[@]}")
new_packages_json=$(jq -cn --argjson pkgs "$packages_json" '
  [range(0; ($pkgs|length)) | {pkgname: $pkgs[.], path: ("packages/" + $pkgs[.])}]
')

write_outputs true "$packages_json" "$new_packages_json"
