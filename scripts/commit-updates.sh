#!/usr/bin/env bash

set -euo pipefail

kazumi_update="${KAZUMI_UPDATE:-false}"
clawx_update="${CLAWX_UPDATE:-false}"
animeko_update="${ANIMEKO_UPDATE:-false}"
kazumi_latest="${KAZUMI_LATEST:-}"
clawx_latest="${CLAWX_LATEST:-}"
animeko_latest="${ANIMEKO_LATEST:-}"
git_ref="${GITHUB_REF:-}"

git config user.name "PaloMiku"
git config user.email "palomiku@outlook.com"

git add \
  packages/kazumi-bin/PKGBUILD \
  packages/clawx-bin/PKGBUILD \
  packages/animeko-appimage-beta/PKGBUILD

updates=()
if [ "$kazumi_update" = "true" ]; then
  updates+=("kazumi-bin:${kazumi_latest}")
fi
if [ "$clawx_update" = "true" ]; then
  updates+=("clawx-bin:${clawx_latest}")
fi
if [ "$animeko_update" = "true" ]; then
  updates+=("animeko-appimage-beta:${animeko_latest}")
fi

if git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

if [ "${#updates[@]}" -eq 0 ]; then
  echo "No update labels found, but files changed; using fallback message"
  git commit -m "Update package definitions"
else
  git commit -m "Update ${updates[*]}"
fi

if [ -z "$git_ref" ]; then
  echo "GITHUB_REF is required for push" >&2
  exit 1
fi

git push origin "HEAD:${git_ref}"
