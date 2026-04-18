#!/usr/bin/env bash

set -euo pipefail

PACKAGES_DIR="packages"

for pkgname in "$@"; do
  pkgdir="${PACKAGES_DIR}/${pkgname}"
  if [ -f "${pkgdir}/PKGBUILD" ]; then
    cd "$pkgdir"
    makepkg --printsrcinfo > .SRCINFO
    cd - > /dev/null
    echo "Generated .SRCINFO for ${pkgname}"
  fi
done