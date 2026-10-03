# Emacs Config Breakdown Plan

## Goal
Break `config/emacs/.config/emacs/init.el` (1769 lines) into atomic per-package config files, organized by concern into directories.

## Structure
```
config/emacs/.config/emacs/
├── init.el                          # just (require) each module in order
├── startup/
│   ├── straight.el                  # bootstrap + freeze/thaw helpers
│   ├── paths.el                     # workspace-dirs, lifeos-dir, config-root-dir
│   └── treesit.el                   # predicate-strip advice
├── core/
│   ├── emacs.el                     # ring, backup, savehist, recentf, auto-revert, ediff, server, line-numbers
│   ├── which-key.el
│   ├── discover.el
│   └── transient.el
├── evil/
│   ├── undo-fu.el
│   ├── evil.el
│   ├── evil-collection.el
│   └── evil-commentary.el
├── tabs/
│   └── centaur-tabs.el
├── appearance/
│   ├── dimmer.el
│   └── ui.el                        # global-hl-line, cursor-type, fringe
├── leader/
│   └── general.el                   # all M-; leader bindings + M-hjkl + H/L tab switch
├── completion/
│   ├── vertico.el
│   ├── vertico-posframe.el
│   ├── orderless.el
│   ├── marginalia.el
│   ├── consult.el
│   ├── consult-dir.el
│   ├── embark.el
│   └── embark-consult.el
├── projects/
│   ├── project.el
│   └── persp-mode.el                # + workspace-switch-to-project, workspace-project-magit
├── git/
│   ├── magit.el
│   ├── magit-todos.el
│   └── diff-hl.el
├── files/
│   └── dirvish.el
├── terminal/
│   ├── vterm.el
│   ├── ghostel.el
│   └── eat.el
├── agents/
│   ├── agent-shell.el               # + all the advice/compat/debug helpers
│   ├── agent-shell-notifications.el
│   ├── knockknock.el
│   ├── agent-shell-manager.el
│   ├── agent-review.el
│   ├── meta-agent-shell.el
│   └── agent-shell-knockknock.el
├── lsp/
│   ├── corfu.el
│   ├── cape.el
│   └── eglot.el
├── org/
│   ├── org.el                       # core org settings + agenda custom commands
│   ├── org-modern.el
│   ├── org-appear.el
│   ├── org-roam.el
│   ├── supertag.el                  # + all the lifeos rule helpers
│   ├── org-ql.el
│   ├── org-super-agenda.el
│   ├── org-wild-notifier.el
│   ├── org-tidy.el
│   ├── org-sticky-header.el
│   ├── org-agenda-property.el
│   ├── org-pomodoro.el
│   ├── org-sidebar.el
│   ├── calfw.el
│   ├── calfw-org.el
│   ├── org-time-budgets.el
│   └── openspec.el
├── markdown/
│   └── markdown-mode.el
├── pdf/
│   └── pdf-tools.el
├── themes/
│   ├── modus-themes.el
│   ├── doom-themes.el
│   ├── nerd-icons.el
│   ├── doom-modeline.el
│   └── fonts.el
└── custom/
    └── helpers.el                   # my/find-file-prompt (only cross-cutting helper)
```

## Source Line Mappings (original init.el)

| New File | Source Lines |
|----------|-------------|
| `startup/straight.el` | 43-58 |
| `startup/paths.el` | 86-109 |
| `startup/treesit.el` | 1-10, 27-39 |
| `core/emacs.el` | 114-155 |
| `core/which-key.el` | 160-167 |
| `core/discover.el` | 169-170 |
| `core/transient.el` | 172-175 |
| `evil/undo-fu.el` | 180 |
| `evil/evil.el` | 182-190 |
| `evil/evil-collection.el` | 192-195 |
| `evil/evil-commentary.el` | 197-199 |
| `tabs/centaur-tabs.el` | 204-251 |
| `appearance/dimmer.el` | 256-260 |
| `appearance/ui.el` | 1692-1693, 1689 |
| `leader/general.el` | 265-342, 345-352, 394-396, 487-490, 511-523, 669-678, 1123-1141, 1578-1582, 1678-1684 |
| `completion/vertico.el` | 357-359 |
| `completion/vertico-posframe.el` | 361-369 |
| `completion/orderless.el` | 378-382 |
| `completion/marginalia.el` | 384-386 |
| `completion/consult.el` | 388-392 |
| `completion/consult-dir.el` | 398-403 |
| `completion/embark.el` | 405-419 |
| `completion/embark-consult.el` | 421-423 |
| `projects/project.el` | 428-442 |
| `projects/persp-mode.el` | 444-464 |
| `git/magit.el` | 500-505 |
| `git/magit-todos.el` | 507-509 |
| `git/diff-hl.el` | 528-542 |
| `files/dirvish.el` | 547-633, 635-667 |
| `terminal/vterm.el` | 714-729 |
| `terminal/ghostel.el` | 732-742 |
| `terminal/eat.el` | 744-754 |
| `agents/agent-shell-notifications.el` | 756-766 |
| `agents/knockknock.el` | 768-777 |
| `agents/agent-shell-manager.el` | 789-795 |
| `agents/agent-review.el` | 797-802 |
| `agents/meta-agent-shell.el` | 804-812 |
| `agents/agent-shell-knockknock.el` | 814-820 |
| `agents/agent-shell.el` | 1079-1121 |
| `lsp/corfu.el` | 1146-1153 |
| `lsp/cape.el` | 1155-1160 |
| `lsp/eglot.el` | 1171-1205 |
| `org/org.el` | 1210-1294 |
| `org/org-modern.el` | 1347-1349 |
| `org/org-appear.el` | 1351-1353 |
| `org/org-roam.el` | 1355-1360 |
| `org/supertag.el` | 1362-1507 |
| `org/org-ql.el` | 1512-1513 |
| `org/org-super-agenda.el` | 1515-1518 |
| `org/org-wild-notifier.el` | 1520-1526 |
| `org/org-tidy.el` | 1528-1532 |
| `org/org-sticky-header.el` | 1534-1539 |
| `org/org-agenda-property.el` | 1541-1545 |
| `org/org-pomodoro.el` | 1547-1553 |
| `org/org-sidebar.el` | 1555-1556 |
| `org/calfw.el` | 1564-1565 |
| `org/calfw-org.el` | 1566-1576 |
| `org/org-time-budgets.el` | 1584-1590 |
| `org/openspec.el` | 1593-1634 |
| `markdown/markdown-mode.el` | 1639-1652 |
| `themes/modus-themes.el` | 1700-1707 |
| `themes/doom-themes.el` | 1709-1721 |
| `themes/nerd-icons.el` | 1723 |
| `themes/doom-modeline.el` | 1724-1738 |
| `themes/fonts.el` | 1657-1688, 1690 |
| `custom/helpers.el` | `my/find-file-prompt` |

## New init.el (minimal)

```elisp
;;; init.el — Emacs config manifest
;; All config lives in individual files under these directories.
;; Load order matters (dependencies first).

;; --- startup ---
(require 'startup/straight nil t)
(require 'startup/paths nil t)
(require 'startup/treesit nil t)

;; --- core ---
(require 'core/emacs nil t)
(require 'core/which-key nil t)
(require 'core/discover nil t)
(require 'core/transient nil t)

;; --- editing ---
(require 'evil/undo-fu nil t)
(require 'evil/evil nil t)
(require 'evil/evil-collection nil t)
(require 'evil/evil-commentary nil t)

;; --- tabs & appearance ---
(require 'tabs/centaur-tabs nil t)
(require 'appearance/dimmer nil t)
(require 'appearance/ui nil t)

;; --- leader keys ---
(require 'leader/general nil t)

;; --- completion ---
(require 'completion/vertico nil t)
(require 'completion/vertico-posframe nil t)
(require 'completion/orderless nil t)
(require 'completion/marginalia nil t)
(require 'completion/consult nil t)
(require 'completion/consult-dir nil t)
(require 'completion/embark nil t)
(require 'completion/embark-consult nil t)

;; --- projects ---
(require 'projects/project nil t)
(require 'projects/persp-mode nil t)

;; --- git ---
(require 'git/magit nil t)
(require 'git/magit-todos nil t)
(require 'git/diff-hl nil t)

;; --- file explorer ---
(require 'files/dirvish nil t)

;; --- terminal ---
(require 'terminal/vterm nil t)
(require 'terminal/ghostel nil t)
(require 'terminal/eat nil t)

;; --- agents ---
(require 'agents/agent-shell-notifications nil t)
(require 'agents/knockknock nil t)
(require 'agents/agent-shell-manager nil t)
(require 'agents/agent-review nil t)
(require 'agents/meta-agent-shell nil t)
(require 'agents/agent-shell-knockknock nil t)
(require 'agents/agent-shell nil t)

;; --- lsp ---
(require 'lsp/corfu nil t)
(require 'lsp/cape nil t)
(require 'lsp/eglot nil t)

;; --- org ---
(require 'org/org nil t)
(require 'org/org-modern nil t)
(require 'org/org-appear nil t)
(require 'org/org-roam nil t)
(require 'org/supertag nil t)
(require 'org/org-ql nil t)
(require 'org/org-super-agenda nil t)
(require 'org/org-wild-notifier nil t)
(require 'org/org-tidy nil t)
(require 'org/org-sticky-header nil t)
(require 'org/org-agenda-property nil t)
(require 'org/org-pomodoro nil t)
(require 'org/org-sidebar nil t)
(require 'org/calfw nil t)
(require 'org/calfw-org nil t)
(require 'org/org-time-budgets nil t)
(require 'org/openspec nil t)

;; --- markdown ---
(require 'markdown/markdown-mode nil t)

;; --- pdf ---
(require 'pdf/pdf-tools nil t)

;; --- themes ---
(require 'themes/modus-themes nil t)
(require 'themes/doom-themes nil t)
(require 'themes/nerd-icons nil t)
(require 'themes/doom-modeline nil t)
(require 'themes/fonts nil t)

;; --- custom helpers ---
(require 'custom/helpers nil t)
```

## Dependency Order Notes

- `general` must load after `evil` (`:after evil`)
- `which-key` loads before `general` (used by general's keybindings)
- `vertico` loads before `consult`, `marginalia`, `embark`
- `consult` loads before `embark-consult`
- `project` and `persp-mode` are independent of evil
- `diff-hl` needs `magit` for hooks
- `agent-shell` needs `agent-shell-notifications`, `knockknock`, etc. loaded before it
- `eglot` needs `corfu`/`cape` for completion integration
- `org-roam` needs `org` loaded first
- `supertag` needs `org` loaded first
- `calfw-org` needs `calfw` and `org`
- `doom-modeline` should load last (it modifies mode-line)

## Edge Cases / Decisions

1. **`custom/helpers.el`** contains only `my/find-file-prompt` — a single cross-cutting helper used by `leader/general.el`. Load it after `leader/general` so the function is available.

2. **`appearance/ui.el`** contains `global-hl-line-mode`, `cursor-type`, and `fringe-mode` settings from lines 1692-1693. These are basic UI chrome, not tied to any package.

3. **`themes/fonts.el`** contains font settings, fullscreen toggle, and theme disable helper. Load after all themes are defined.

4. **`startup/treesit.el`** contains the predicate-strip advice. Must load before any package that restores `.ts`/`.tsx` buffers (notably `persp-mode`).

5. **Agent-shell advice functions** (`my/agent-shell--*`) all live in `agents/agent-shell.el` since they're tightly coupled to the agent-shell package.

6. **`my/switch-theme`** lives in `themes/fonts.el` alongside the font helpers.

7. **`my/workspace-switch-to-project`** and **`my/workspace-project-magit`** live in `projects/persp-mode.el` since they're workspace/project switching helpers.

8. **`my/org-*`** helpers live in `org/org.el` since they're org-specific.

9. **`my/lifeos-*`** helpers live in `org/supertag.el` since they're supertag helpers.

10. **`my/calfw-open`** lives in `org/calfw-org.el`.

11. **`my/openspec-*`** helpers live in `org/openspec.el`.

12. **`my/toggle-vertico-posframe`** lives in `completion/vertico-posframe.el`.

## Execution Steps

1. Create all directories under `config/emacs/.config/emacs/`
2. For each file, extract the relevant `use-package` block(s) and custom functions from `init.el`
3. Write the file with the extracted content
4. Replace `init.el` content with the minimal manifest above
5. Test by opening Emacs and verifying all packages load correctly