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


## Current Backlog

emacs:
- emacs theme fixing
- square brackets for next / previous (hunk, error....) 
- tsconfig project errors display (not just file)
- agent-shell
- agent-review
- agent-shell-manager
- agent-shell-knockknock / agent-shell-notifications (configured to keep notifying at an interval if I don't respond / actively acknowledge somehow)
- meta-agent-shell
- acp-mobile
- ghostel - installed
- tts
- investigate eca
- investigate splitting init.el without breaking
- emacs webview
https://melpa.org/#/popup
https://melpa.org/#/hydra
https://melpa.org/#/hl-todo
evil-surround
restart-emacs
evil-visualstar
json-mode
org-pomodoro
org-ql
org-present
org-projectile
org-project-capture
org-gcal
calfw-org
org-sticky-header
org-beautify-theme
org-timeline
org-drill
org-sidebar
org-dashboard
org-wild-notifier
org-agenda-property
ob-typescript
org-clock-convenience
org-mobile-sync
org-table-sticky-header
org-time-budgets
org-analyzer
org-tidy
org-side-tree
timesheet


general:
- research wifi failing, requiring restart after 2 days
- think about and setup cron jobs for agents
- look into omarchy's webapp launching system
- Learn / adapt system ergonomics (floating windows, keybindings) 
- Bitwarden
- LocalSend
- Setup agent long-term memory + share across PC/Mac.
- Explore feasible ways to respond via phone to agents blocked on my input.
- nushell
- Figure out efficient ways to do the most common/important things as a general user + software developer.
- Setup jj
- setup dcli (declarative arch)
- Fix my storage setup
- Configure auto shutdown after 24h of inactivity

