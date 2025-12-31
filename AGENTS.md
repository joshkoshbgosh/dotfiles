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
* Shell: bash (for now at least)
* Package managers: `pacman` / `paru` (or `yay` if present)

## High-level work priorities (most to least)

* Improve scrolling (reverse + smooth)
* Learn / modify Hyprland ergonomics:
  * common workflows for floating windows (focus switching, toggling float, pinning, rules)
   * keybinding improvements
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
* Modify omarchy's keybinding cheat sheet that 'super + k' reveals by default in omarchy

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
* Never run “curl | sh” or similar unsafe execution of shell code fetched from the web; prefer package manager installs. If "curl | sh" is needed, tell the user you're blocked on it.
* If `sudo` is required, explain why and what will change.
* Never store credentials in tracked files. If a tool needs secrets:

  * use `~/.config/...` local-only files
  * use environment variables
  * document setup steps without embedding secrets

## What the agent should ask for when needed

If you need more info, request:

* `hyprctl clients` output (trimmed if long)
* `hyprctl monitors` output
* any relevant config file paths used by this repo (e.g., where `hyprland.conf` actually lives)

## Current backlog (explicit)
* Setup Workspace as per the 'Workspace Configuration' section below
* Reverse scrolling direction / smoother scrolling
* Change keybindings (Hyprland/Omarchy)
* Install/setup hyprwhispr
* Set up LocalSend
* Install/setup Bitwarden
* “oh my opencode” workflow
* memento MCP server for cross-device long-term memory (PC/Mac)
* Learn floating-window focus workflows
* Parallel niri experiment

## Workspace Configuration

Workspace 1 (dev)


# Agents.md

This repo contains my Omarchy (Arch-based) + Hyprland setup and supporting scripts. Treat this file as the source of truth for how to extend/modify my dotfiles in a reproducible way.

## Environment snapshot

- Distro: Omarchy (Arch-based)
- Compositor: Hyprland (Wayland)
- Hyprland version: 0.52.2
- GPU: NVIDIA 3060
- Terminal: Ghostty
- Shell: bash
- Package tooling: pacman + AUR (yay), Omarchy app installer menus
- Dotfiles mgmt: GNU Stow

### Known gotchas
- Hyprland `windowrule` syntax must match v0.52.2 behavior:
  - Use v2 matcher form like `class:(steam)` (NOT `match:class ...`).
- Steam Big Picture lag fix: Steam → Settings → Interface → enable GPU accelerated rendering in web views.

## Repo conventions

### Stow layout
Packages live under: `~/Work/dotfiles/config/<package>/...` where each package mirrors `$HOME` paths.

Example:
- `config/hypr/.config/hypr/...`  → stows into `~/.config/hypr/...`
- `config/bin/.local/bin/...`     → stows into `~/.local/bin/...`

Stow usage (from config dir):
```bash
cd ~/Work/dotfiles/config
stow -t ~ hypr bin desktop

Avoid --adopt unless explicitly needed; prefer backing up conflicting real files and then stowing.

### Stow layout

Use small, purpose-specific files and source them from the main Hyprland config (or Omarchy’s suggested includes).

Preferred:

~/.config/hypr/monitors.conf (monitor definitions / scale)

~/.config/hypr/autostart.conf (exec-once lines; Omarchy already provides)

~/.config/hypr/hyprland.conf (minimal persistent rules; currently only Steam placement)

Optionally additional sourced files as the setup grows (keybinds.conf, workspaces.conf, etc.)

Current config state (high level)
Monitor scale

Goal: readable global UI scale.

DP-1 scale set to 1.33

GDK_SCALE set to 1 (avoid GTK-only scaling hacks unless needed)

Steam behavior

Requirement: Steam should open in the same place every time.

Only persistent workspace rule desired: Steam → workspace 4.

Big Picture launched via steam -gamepadui (autostart is optional).

Workspace plan (target layout)

1 = dev

left: browser (Chrome/Chromium)

top-right: Neovim in Ghostty

bottom-right: Ghostty shell

2 = communication

Thunderbird

Discord (currently as webapp or equivalent)

3 = organization

Notion webapp

Notion Calendar webapp

4 = gaming

Steam Big Picture

Scratchpad (special workspace)

btop (or similar)

Spotify

Deterministic autostart requirement

I’m OK with scripts, but I do NOT want “sleep and hope” startup.
If we need ordering:

Use a script that waits deterministically by querying hyprctl clients -j and matching windows (requires jq).

Prefer event/poll-based readiness checks over fixed sleeps.

Keep orchestration minimal and maintainable.

Package reproducibility

I’m capturing installed packages in this repo (via capture-packages.sh and committed output). This is meant as a baseline “rebuild list” for a new machine.

Notes:

Some removals are tracked manually in a text file (I decided not to automate removals for now).

Installation is typically done “the Omarchy way” (launcher menu) or via pacman/yay as needed.

What agents should do / not do
Do

Keep configs modular and stow-friendly.

Prefer Hyprland-native configuration and minimal rules.

When writing startup/layout logic:

Avoid fixed sleeps when possible.

If sequencing is needed, implement deterministic waits using hyprctl clients -j + jq.

When adding webapps:

Launch via gtk-launch <desktop-id> where <desktop-id> corresponds to a .desktop in ~/.local/share/applications.

Maintain bash compatibility.

Avoid

Introducing tmux as the default solution for layout.

Large monolithic Hyprland configs without structure.

Hard-coding machine-specific assumptions without documenting them (monitor names, paths, app_ids).

Remaining dotfiles work (next actions)
Dotfiles / stow hygiene

Ensure Hyprland config files are all stowed from config/hypr/....

Ensure any helper scripts are stowed from config/bin/... (or under Hypr scripts directory if chosen).

Confirm conflicts are resolved via backup (not --adopt) unless necessary.

Hyprland startup + layout (main deliverable)

Implement reproducible startup that creates:

workspace 1 (browser left, ghostty+neovim top-right, ghostty shell bottom-right)

workspace 2: thunderbird + discord

workspace 3: notion + notion calendar

workspace 4: steam big picture

scratchpad: spotify + btop

Only persistent rule: Steam workspace placement.

Webapp IDs

Identify desktop IDs for:

Discord webapp

Notion webapp

Notion Calendar webapp

Store launch commands in autostart or in the deterministic session script.

Deferred TODO list (do later; don’t solve unless asked)

System/UI:

Reverse scrolling direction / make scrolling smoother if possible.

Steam + Hyprland quirks:

(was) scaling/zoom issue fixed via Steam UI scaling + GPU webview accel toggle

remaining: tiling/floating behavior polish if needed

Learn how to deal with floating windows (focus, move, toggle, rules).

Tooling:

Setup git (global config, SSH keys, signing if desired).

Change keybindings (Hyprland / Omarchy).

Setup LocalSend.

Install + setup Bitwarden (unify passwords across platforms).

Setup hyprwhispr.

Opencode ecosystem:

Setup “oh my opencode”.

Setup memento MCP server with opencode for long-term memory + share across PC/Mac.

Explore feasible ways to respond via phone to agents blocked on my input.

Experiments:

Parallel niri experiment alongside Hyprland/Omarchy.

Other:

Use my brother’s Ghostty/Neovim configs from his public repo (integrate cleanly).

Setup some sort of remote desktop experience.

Make it so I don’t have to enter my password after idle (desktop; low security concern).

Figure out most common/important things to know how to do on my PC as a general user + software developer.

Quick reference commands

Hyprland:

Show windows: hyprctl clients

JSON windows: hyprctl clients -j

Reload: hyprctl reload

Monitor info: hyprctl monitors

Stow:

cd ~/Work/dotfiles/config && stow -t ~ hypr bin desktop

Remove package symlinks: stow -D -t ~ <package>

Webapps:

List local desktop entries: ls ~/.local/share/applications

Launch by desktop id: gtk-launch <desktop-id>
