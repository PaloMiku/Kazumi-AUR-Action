#!/usr/bin/env bash

set -euo pipefail

package_names=()

if [ "$#" -gt 0 ]; then
  package_names=("$@")
elif [ -n "${NEW_PACKAGES_JSON:-}" ]; then
  mapfile -t package_names < <(printf '%s' "$NEW_PACKAGES_JSON" | jq -r '.[] | if type == "object" then .pkgname else . end')
fi

git_add_pkgs=()

for pkgname in "${package_names[@]}"; do
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

git -c user.name="PaloMiku" -c user.email="palomiku@outlook.com" commit -m "Add new AUR packages: ${package_names[*]}"

echo "Committed new packages: ${package_names[*]}"
