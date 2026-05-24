## Hyprland Guidelines
- Use v2 matcher syntax: `class:(steam)` (NOT `match:class...`)
- Use `hyprctl clients`, `hyprctl monitors` for diagnosis

- Deterministic startup: prefer `hyprctl clients -j + jq` over fixed sleeps
## Quick Commands
```bash:
hyprctl clients -j   # JSON window list
hyprctl monitors     # monitor info
hyprctl reload       # reload config
```

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
