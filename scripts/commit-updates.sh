#!/usr/bin/env bash

set -euo pipefail

updated_packages_json="${UPDATED_PACKAGES:-[]}"
git_ref="${GITHUB_REF:-}"

if ! command -v makepkg >/dev/null 2>&1; then
  echo "makepkg is required for commit-updates but was not found in PATH." >&2
  exit 1
fi

mapfile -t updated_packages < <(printf '%s' "$updated_packages_json" | jq -r '.[]')

if [ "${#updated_packages[@]}" -eq 0 ]; then
  echo "No updated packages provided."
  exit 0
fi

paths_to_add=()
update_labels=()

for pkgname in "${updated_packages[@]}"; do
  pkgdir="packages/${pkgname}"

  if [ ! -d "$pkgdir" ]; then
    echo "Missing package directory: ${pkgdir}" >&2
    exit 1
  fi

  if [ ! -f "${pkgdir}/PKGBUILD" ]; then
    echo "Missing PKGBUILD in ${pkgdir}" >&2
    exit 1
  fi

  (
    cd "$pkgdir"
    makepkg --printsrcinfo > .SRCINFO
  )
  paths_to_add+=("${pkgdir}/PKGBUILD" "${pkgdir}/.SRCINFO")

  pkgver=$(sed -nE "s/^pkgver=\"?([^\"']+)\"?$/\1/p" "${pkgdir}/PKGBUILD" | head -n1)
  update_labels+=("${pkgname}:${pkgver}")
done

git add "${paths_to_add[@]}"

if git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

git -c user.name="PaloMiku" -c user.email="palomiku@outlook.com" commit -m "Update ${update_labels[*]}"

if [ -z "$git_ref" ]; then
  echo "GITHUB_REF is required for push" >&2
  exit 1
fi

git push origin "HEAD:${git_ref}"
