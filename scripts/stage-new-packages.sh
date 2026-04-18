#!/usr/bin/env bash

set -euo pipefail

git_add_pkgs=()

for pkgname in "$@"; do
  pkgdir="packages/${pkgname}"
  if [ -f "${pkgdir}/PKGBUILD" ]; then
    git_add_pkgs+=("${pkgdir}/PKGBUILD" "${pkgdir}/.SRCINFO" "${pkgdir}/package.json")
  fi
done

if [ ${#git_add_pkgs[@]} -eq 0 ]; then
  echo "No packages to stage"
  exit 0
fi

git add "${git_add_pkgs[@]}"

if git diff --cached --quiet; then
  echo "No changes to commit"
  exit 0
fi

git -c user.name="PaloMiku" -c user.email="palomiku@outlook.com" commit -m "Add new AUR packages: $*"

echo "Committed new packages: $*"