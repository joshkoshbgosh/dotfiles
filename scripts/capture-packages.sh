#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$(dirname "$0")/../packages"

pacman -Qqe > "$(dirname "$0")/../packages/pkglist-pacman.txt"
pacman -Qqm > "$(dirname "$0")/../packages/pkglist-aur.txt"

echo "Wrote:"
echo "  packages/pkglist-pacman.txt (explicit official packages)"
echo "  packages/pkglist-aur.txt    (foreign/AUR packages)"
