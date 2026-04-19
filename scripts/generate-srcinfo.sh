#!/usr/bin/env bash

set -euo pipefail

PACKAGES_DIR="packages"

package_names=()

if [ "$#" -gt 0 ]; then
  package_names=("$@")
elif [ -n "${NEW_PACKAGES_JSON:-}" ]; then
  mapfile -t package_names < <(printf '%s' "$NEW_PACKAGES_JSON" | jq -r '.[] | if type == "object" then .pkgname else . end')
fi

for pkgname in "${package_names[@]}"; do
  pkgdir="${PACKAGES_DIR}/${pkgname}"
  if [ -f "${pkgdir}/PKGBUILD" ]; then
    cd "$pkgdir"
    makepkg --printsrcinfo > .SRCINFO
    cd - > /dev/null
    echo "Generated .SRCINFO for ${pkgname}"
  fi
done
