;; -*- lexical-binding: t -*-
;;; keys/global.el --- personal key bindings

;; The `M-;' leader is gone, and with it `general' and the per-state
;; auxiliary keymaps it was built on.  Evil is gone too, so everything below is
;; a plain `global-map' binding on `C-c', the prefix Emacs reserves for the
;; user, and it applies in every buffer regardless of editing mode.
;;
;; Single keystroke, no sub-trees: `C-c P' is `project-find-file', not
;; `C-c p f'.  Keeping the whole table in one file also means it no longer
;; depends on load order or on a package that defines a prefix map.
;;
;; Not bound here on purpose:
;;   `C-c w'  org-timegrid-week  (bound in org/org-timegrid.el)
;;   `C-c r'  diff-review    (prefix owned by diff-review)
;; Mode-local `C-c ...' bindings still win inside their own buffers, which is
;; exactly why `C-c' is the right prefix for personal keys.
;;
;; Terminals already treat `C-c' as an Emacs prefix and give the rest of the
;; chord to Emacs, so the table below works inside vterm, eat and ghostel too:
;; each keeps `C-c C-c' for the shell (SIGINT) and only claims uppercase
;; `C-c C-x'/`C-c M-x' continuations, none of which collide with the
;; single-key bindings here.  More precisely, a terminal's `C-c' prefix map
;; only shadows the exact keys it binds; anything else falls through to
;; `global-map', which is why `C-c f' opens a file from inside a shell buffer
;; while `C-c C-c' still interrupts the running process.

;; --- files and buffers ---
(keymap-set global-map "C-c f" #'my/find-file-prompt)
(keymap-set global-map "C-c b" #'consult-buffer)
(keymap-set global-map "C-c R" #'recentf-open-files)
;; Browse a GitHub/Codeberg repo without cloning it (files/remoto.el).
(keymap-set global-map "C-c B" #'remoto-browse)

;; --- search and jump ---
(keymap-set global-map "C-c s" #'consult-ripgrep)
(keymap-set global-map "C-c l" #'consult-line)
(keymap-set global-map "C-c i" #'consult-imenu)
(keymap-set global-map "C-c o" #'consult-outline)

;; --- projects ---
(keymap-set global-map "C-c p" #'project-switch-project)
(keymap-set global-map "C-c P" #'project-find-file)

;; --- diagnostics ---
(keymap-set global-map "C-c e" #'consult-flymake)

;; --- notes ---
;; Org installs these itself, but only once `org-agenda'/`org-capture' have
;; loaded; they were leader-only before, so bind them explicitly.
(keymap-set global-map "C-c a" #'org-agenda)
(keymap-set global-map "C-c c" #'org-capture)
(keymap-set global-map "C-c n" #'org-roam-node-find)
(keymap-set global-map "C-c N" #'org-roam-node-insert)
(keymap-set global-map "C-c g" #'my/lifeos-agenda)
(keymap-set global-map "C-c j" #'my/org-open-today)

;; --- agents ---
(keymap-set global-map "C-c A" #'agent-shell)
(keymap-set global-map "C-c S" #'agent-shell-send-region)
(keymap-set global-map "C-c M" #'agent-shell-manager-toggle)
(keymap-set global-map "C-c V" #'agent-review)

;; --- workspaces (space-tree) ---
;; Not C-c TAB / C-c [ / C-c ]: those are `org-ctrl-c-tab',
;; `org-agenda-file-to-front' and `org-remove-file' in org buffers, which is
;; exactly where switching spaces is most wanted.
(keymap-set global-map "C-c v" #'space-tree-switch-space-by-name)
(keymap-set global-map "C-c x" #'space-tree-go-right)
(keymap-set global-map "C-c z" #'space-tree-go-left)

;; --- terminals ---
(keymap-set global-map "C-c T" #'vterm)

;; --- window navigation ---
;; M-hjkl for window navigation (plain global bindings, work in every buffer)
;; Previously bound to windmove-*; keep those bindings but ensure they take
;; precedence over any mode-local bindings by binding after module load.
(keymap-set global-map "M-h" #'windmove-left)
(keymap-set global-map "M-j" #'windmove-down)
(keymap-set global-map "M-k" #'windmove-up)
(keymap-set global-map "M-l" #'windmove-right)
