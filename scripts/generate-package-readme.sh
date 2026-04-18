#!/bin/bash
set -e

generate_readme() {
    local pkgdir="$1"
    local pkgname
    pkgname=$(basename "$pkgdir")

    if [[ ! -f "$pkgdir/package.json" ]]; then
        echo "Skipping $pkgname: no package.json found"
        return 1
    fi

    local pkgver pkgdesc url repo release_strategy
    pkgver=$(grep -m1 '^pkgver=' "$pkgdir/PKGBUILD" | cut -d'=' -f2 | tr -d '"')
    pkgdesc=$(grep -m1 '^pkgdesc=' "$pkgdir/PKGBUILD" | cut -d'=' -f2 | tr -d '"')
    url=$(grep -m1 '^url=' "$pkgdir/PKGBUILD" | cut -d'=' -f2 | tr -d '"')

    repo=$(jq -r '.repo // empty' "$pkgdir/package.json")
    release_strategy=$(jq -r '.release_strategy // empty' "$pkgdir/package.json")

    if [[ -z "$repo" ]]; then
        echo "Skipping $pkgname: no repo in package.json"
        return 1
    fi

    local upstream_url="https://github.com/$repo"
    local aur_pkgurl="https://aur.archlinux.org/packages/$pkgname"
    local git_sha
    git_sha=$(cd "$pkgdir" && git rev-parse HEAD 2>/dev/null | head -c7 || echo "")

    local update_time=""
    if git -C "$pkgdir" log -1 --format=%ci >/dev/null 2>&1; then
        update_time=$(git -C "$pkgdir" log -1 --format=%ci | sed 's/ +0000/ UTC/')
    fi

    cat > "$pkgdir/README.md" <<EOF
# $pkgname

[$pkgname]($aur_pkgurl) - $pkgdesc

## Package Info

| Field | Value |
|-------|-------|
| Package Name | \`$pkgname\` |
| Current Version | \`$pkgver\` |
| Upstream Repo | [$repo]($upstream_url) |
| Release Strategy | \`$release_strategy\` |
| AUR Page | [$pkgname @ AUR]($aur_pkgurl) |

## Installation

\`\`\`bash
# Using yay
yay -S $pkgname
# Using paru
paru -S $pkgname
\`\`\`

## Build

\`\`\`bash
cd packages/$pkgname
makepkg -si
\`\`\`

## Links

- [Upstream Release]($upstream_url/releases)
- [AUR Page]($aur_pkgurl)

EOF

    if [[ -n "$update_time" ]]; then
        echo "Last Updated: $update_time" >> "$pkgdir/README.md"
    fi

    echo "Generated README.md for $pkgname"
}

if [[ -n "$1" && -d "$1" ]]; then
    generate_readme "$1"
else
    for pkgdir in packages/*; do
        if [[ -d "$pkgdir" && -f "$pkgdir/package.json" ]]; then
            generate_readme "$pkgdir"
        fi
    done
fi