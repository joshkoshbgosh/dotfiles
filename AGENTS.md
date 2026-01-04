# AGENTS.md

My dotfiles repo, based on omarchy, and using stow

## Repo Structure (Stow)
```
config/<package>/... → ~/<path>
- config/hypr/.config/hypr/ → ~/.config/hypr/
- config/bin/.local/bin/ → ~/.local/bin/
- config/desktop/.local/share/applications/ → ~/.local/share/applications/
```

## Stow Commands
```bash
cd ~/Work/dotfiles/config && stow -t ~ hypr bin desktop
stow -D -t ~ <package>  # remove symlinks
```

## Key Conventions
- Keep configs modular; prefer small sourced files over monolithic configs
- Avoid sweeping rewrites without clear payoff
- Never add secrets to repo (use ~/.config/ local-only files or env vars)
- Small, focused commits with clear documentation

## Hyprland Guidelines
- Use v2 matcher syntax: `class:(steam)` (NOT `match:class...`)
- Use `hyprctl clients`, `hyprctl monitors` for diagnosis
- Deterministic startup: prefer `hyprctl clients -j + jq` over fixed sleeps

## Current Backlog
- look into omarchy's webapp launching system
- Reverse/smooth scrolling
- Workspace setup (See 'Workspace plan' section)
- Learn / adapt system ergonomics (floating windows, keybindings) 
- Bitwarden
- LocalSend
- hyprwhispr
- Setup “oh my opencode”.
- Setup memento MCP server with opencode for long-term memory + share across PC/Mac.
- Explore feasible ways to respond via phone to agents blocked on my input.
- try out ben's ghostty / nvim configs
- zsh/ohmyzsh
- niri experiment
- Change lockscreen / idle experience
- Figure out efficient ways to do the most common/important things as a general user + software developer.
- Setup jj
- setup claude code
- setup dcli (declarative arch)
- Setup Steam Remote Play
- Fix my storage setup

## Quick Commands
```bash
hyprctl clients -j   # JSON window list
hyprctl monitors     # monitor info
hyprctl reload       # reload config
```

## Do's & Don'ts
- DO: Modular configs, Hyprland-native solutions, bash compatibility
- DON'T: tmux for layout, hardcoded machine assumptions, `curl | sh`

## Workspace plan

On start, I want specific instances of apps initially launched in specific workspaces, tiled in the way I want. Right now, the only workspace rule (i.e: rules for which workspace new instances of apps should go to) I have is for steam, but I think it makes sense for every app except for new browser instances and new terminal instances to have workspace rules. I would love a declarative + deterministic way to do this, but I haven't found a way (yet) to get the apps I want launched on start in the workspace configuration that I want. dwindle's 'preserve_split' and `layoutmsg preselect` seem promising.

I’m OK with scripts, if necessary to get deterministic tiling, but I do NOT want “sleep and hope” startup (prefer: declarative + deterministic -> script + event based scheduling -> script + poll based scheduling.

Keep orchestration minimal and maintainable.

Here is the workspace layout I want:

### 1 = dev

left: browser (Chrome/Chromium)

top-right: Neovim in Ghostty

bottom-right: Ghostty shell

### 2 = communication

Thunderbird

Discord (currently as webapp or equivalent)

### 3 = organization

Notion webapp

Notion Calendar webapp

### 4 = gaming

Steam Big Picture

### Scratchpad (special workspace) = instant access

btop (or similar)

Spotify

## Notes:

- Steam Big Picture lag fix: Steam → Settings → Interface → enable GPU accelerated rendering in web views.
