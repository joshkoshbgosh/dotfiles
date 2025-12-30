# AGENTS.md (Dotfiles / Omarchy / Hyprland)

## Purpose of this repo

This repository is my personal **dotfiles** for an **Omarchy (Arch-based) Linux machine**, primarily configured around **Hyprland** and related Wayland tooling.

Primary goals:

* Keep a **reproducible**, **well-documented**, and **incrementally maintainable** configuration.
* Resolve specific UX issues (scroll direction/smoothness; Steam + Hyprland tiling/scale problems; floating-window focus workflow).
* Evolve toward a “daily-driver” setup that supports both **general use** and **software development**.

## Operating environment assumptions

* OS: Arch-based (Omarchy)
* Display server: Wayland
* WM/Compositor: Hyprland (recently seen: **Hyprland 0.52.2**)
* Shell: likely `fish` (when providing commands, prefer shell-agnostic where possible; otherwise include both `bash` and `fish` notes)
* Package managers: `pacman` / `paru` (or `yay` if present)

## High-level work priorities (most to least)

1. Fix Steam + Hyprland issues:

   * Steam ignoring tiling (centering/floating over tiled apps)
   * Steam UI scaling (huge fonts / zoom)
2. Improve scrolling:

   * reverse scrolling direction
   * smoother scrolling (touchpad/mouse)
3. Hyprland ergonomics:

   * common workflows for floating windows (focus switching, toggling float, pinning, rules)
   * keybinding improvements
4. Developer setup:

   * git setup (identity, ssh keys if applicable, safe defaults)
5. Utilities:

   * LocalSend
   * Bitwarden
6. Experiments / future:

   * `hyprwhispr`
   * “oh my opencode” setup and workflow
   * memento MCP server for long-term memory shared across PC/Mac
   * parallel niri experiment

## Non-goals / boundaries

* Do not introduce sweeping rewrites of config structure unless there is a clear payoff.
* Avoid adding heavy frameworks or “dotfiles managers” unless explicitly requested.
* Never add secrets (API keys, tokens, private hostnames, SSH private keys) to the repo.

## Repository conventions

When you add or change files:

* Prefer small, focused commits and changesets.
* Preserve existing structure unless it’s clearly broken.
* If you create new config modules, document:

  * what it controls
  * how it’s enabled
  * how to rollback

### Documentation requirements

For any non-trivial change, update `README.md` (or a `docs/` note) with:

* What changed
* Why it changed
* How to validate
* How to revert

## Change workflow expected from agents

When you propose or apply changes, follow this structure:

1. **Diagnosis**

   * Identify the problem and the likely root cause(s).
   * List what evidence/logs/versions matter (Hyprland version, monitor scale, env vars, etc).

2. **Minimal fix first**

   * Implement the smallest change likely to fix the issue.
   * Only escalate to more complex solutions if minimal fix fails.

3. **Validation steps**

   * Provide exact commands to test changes.
   * Provide how to inspect whether Hyprland rules are taking effect.

4. **Rollback**

   * Always include how to undo the change.

## Hyprland-specific guidance

* Prefer modern Hyprland config syntax and confirm it matches the installed version.
* Use `hyprctl` for verification steps whenever possible.
* Treat window rules carefully: ensure correct rule syntax and matching (class/title/appid), and avoid conflicting rules.

When diagnosing window behavior:

* Ask Hyprland what it sees:

  * `hyprctl clients`
  * `hyprctl activewindow`
  * `hyprctl monitors`
* For Steam specifically, expect that class/title/appid might differ between:

  * native steam
  * steam-runtime
  * games launched via steam

## Steam + Hyprland issue handling (rules of thumb)

When addressing Steam tiling/float/centering and scaling:

* Prefer compositing rules/env vars that affect **Steam only**, not global scaling.
* Avoid blanket `GDK_SCALE`/`QT_SCALE_FACTOR` system-wide unless necessary.
* If a solution depends on XWayland vs Wayland-native behavior, document which mode Steam is using and how to confirm it.

## Input/scrolling guidance

For reversing/smoothing scrolling:

* Determine whether the device is managed by:

  * libinput (most common)
  * specific vendor driver
  * a desktop environment layer
* Prefer scoped changes:

  * touchpad only vs mouse only (if possible)
* Document device identifiers and where the setting is applied (Hyprland, libinput, udev, etc).

## Keybindings and “daily-driver” ergonomics

Keybinding changes should:

* Avoid collisions with existing Omarchy defaults unless you explicitly replace them.
* Include a short “cheat sheet” entry in docs:

  * focus change
  * move window
  * toggle float
  * pin
  * fullscreen
  * scratchpad (if used)

## Developer preferences (how to write output)

* Be direct and structured: headings, short sections, explicit steps.
* Provide copy/paste-ready commands.
* When making changes, include:

  * file paths
  * exact snippets to insert/replace
  * any version-dependent notes
* For troubleshooting, prefer deterministic checks over “try X and see”.

## Safety and system integrity

* Do not recommend destructive commands unless explicitly required and clearly explained.
* Avoid “curl | sh” unless unavoidable; prefer package manager installs.
* If `sudo` is required, explain why and what will change.
* Never store credentials in tracked files. If a tool needs secrets:

  * use `~/.config/...` local-only files
  * use environment variables
  * document setup steps without embedding secrets

## What the agent should ask for when needed

If you need more info, request:

* `hyprctl clients` output (trimmed if long)
* `hyprctl monitors` output
* the exact Steam launch method (native package vs flatpak vs runtime)
* any relevant config file paths used by this repo (e.g., where `hyprland.conf` actually lives)

## Current backlog (explicit)

* Reverse scrolling direction / smoother scrolling
* Fix Steam tiling rules (Steam centering/floating, ignoring tiling)
* Fix Steam UI scaling/zoom
* Set up git (identity + sane defaults)
* Change keybindings (Hyprland/Omarchy)
* Install/setup hyprwhispr
* Set up LocalSend
* Install/setup Bitwarden
* “oh my opencode” workflow
* memento MCP server for cross-device long-term memory (PC/Mac)
* Learn floating-window focus workflows
* Parallel niri experiment

