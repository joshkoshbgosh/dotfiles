# AGENTS.md

This is a dotfiles repository for system configuration.

## Shell Scripts
- Scripts are in `scripts/` directory
- Use `bash` for all scripts
- Use strict mode: `set -euo pipefail`
- Use `shellcheck` for linting: `shellcheck scripts/*.sh`

## Config Files
- Hyprland config: `config/hypr/.config/hypr/`
- Desktop entries: `config/desktop/.local/share/applications/`
- Follow existing indentation and formatting patterns in each file

## Adding New Packages
- Run `scripts/capture-packages.sh` to regenerate package lists
- Document AUR packages in `packages/pkglist-aur.txt`
- Document official packages in `packages/pkglist-pacman.txt`
- Document removed packages in `packages/pkg-remove.txt`
