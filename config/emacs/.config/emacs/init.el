;; -*- lexical-binding: t -*-
;;; init.el — Emacs config manifest
;; All config lives in individual files under these directories.
;; Load order matters (dependencies first).

(defvar my/config-root
  (file-name-directory
   (file-truename (or load-file-name user-init-file buffer-file-name
                      ;; Falls back here when called from `M-:' or a REPL,
                      ;; where all three of the above are nil.
                      (expand-file-name "init.el" user-emacs-directory))))
  "Directory containing this Emacs config.")

(defvar my/failed-modules nil
  "Modules that failed to load during startup.")

(defun my/load-module (path)
  "Load module PATH, isolating its failures.

A module that signals an error is reported and skipped instead of aborting
the rest of init.el.  One broken optional package (a half-cloned straight
checkout, a missing executable) used to leave a half-configured Emacs with
no keybindings at all; now it costs exactly that one module.

With `--debug-init' the error is re-signalled, so development still stops at
the real problem."
  (let ((file (expand-file-name (concat path ".el") my/config-root)))
    (condition-case err
        (load file nil t t)
      (error
       (push (cons path (error-message-string err)) my/failed-modules)
       (message "my/load-module: %s failed: %s" path (error-message-string err))
       (when init-file-debug
         (signal (car err) (cdr err)))
       nil))))

;; --- startup ---
(my/load-module "startup/straight")
(my/load-module "startup/paths")
(my/load-module "startup/treesit")

;; --- core ---
(my/load-module "core/emacs")
(my/load-module "core/which-key")
(my/load-module "core/discover")
(my/load-module "core/transient")
;; Command-frequency tracking (#13): `M-x keyfreq-show'
(my/load-module "core/keyfreq")

;; --- editing ---
(my/load-module "evil/undo-fu")
(my/load-module "evil/evil")
(my/load-module "evil/evil-collection")
(my/load-module "evil/evil-commentary")

;; --- tabs & appearance ---
;; Centaur-tabs disabled: the tab strip was visual noise (#10).
;; The module file is kept on disk but no longer loaded.
(my/load-module "appearance/dimmer")
(my/load-module "appearance/ui")

;; --- keys ---
;; Personal bindings on C-c. The old M-; leader is gone.
(my/load-module "keys/global")

;; --- completion ---
(my/load-module "completion/vertico")
(my/load-module "completion/vertico-posframe")
(my/load-module "completion/orderless")
(my/load-module "completion/marginalia")
(my/load-module "completion/consult")
(my/load-module "completion/consult-dir")
(my/load-module "completion/embark")
(my/load-module "completion/embark-consult")
;; Pull-request style diff review (#5)
(my/load-module "completion/diff-review")

;; --- projects ---
(my/load-module "projects/project")

;; --- git ---
(my/load-module "git/magit")
;; Forge: issues and pull requests in magit (#6)
(my/load-module "git/magit-forge")
(my/load-module "git/magit-todos")
(my/load-module "git/diff-hl")

;; --- windows ---
;; Popup management: `C-`' toggles the latest help/compilation/grep popup.
(my/load-module "window/popper")

;; --- file explorer ---
(my/load-module "files/dirvish")

;; --- terminal ---
(my/load-module "terminal/vterm")
(my/load-module "terminal/ghostel")
(my/load-module "terminal/eat")

;; excali-mode: canvas API only, inert below Emacs 32 (#17)
(my/load-module "modes/excali-mode")

;; --- agents ---
(my/load-module "agents/agent-shell-notifications")
(my/load-module "agents/knockknock")
(my/load-module "agents/agent-shell-manager")
(my/load-module "agents/agent-review")
(my/load-module "agents/meta-agent-shell")
(my/load-module "agents/agent-shell-knockknock")
(my/load-module "agents/agent-shell")

;; embr: Chromium rendered inside Emacs (#18)
(my/load-module "browser/embr")

;; --- lsp ---
(my/load-module "lsp/corfu")
(my/load-module "lsp/cape")
(my/load-module "lsp/eglot")

;; --- org ---
(my/load-module "org/org")
(my/load-module "org/org-modern")
(my/load-module "org/org-appear")
(my/load-module "org/org-roam")
(my/load-module "org/lifeos-planning")
(my/load-module "org/lifeos-forecast")
(my/load-module "org/lifeos-schedule")
(my/load-module "org/lifeos-solver")
(my/load-module "org/lifeos-agenda")
(my/load-module "org/lifeos-supertag")
(my/load-module "org/supertag")
(my/load-module "org/lifeos-task-export")
(my/load-module "org/org-ql")
(my/load-module "org/org-super-agenda")
(my/load-module "org/org-wild-notifier")
(my/load-module "org/org-tidy")
(my/load-module "org/org-sticky-header")
(my/load-module "org/org-agenda-property")
(my/load-module "org/org-pomodoro")
(my/load-module "org/org-sidebar")
(my/load-module "org/org-gcal")
(my/load-module "org/calfw")
(my/load-module "org/calfw-org")
;; Week calendar over org files (#7)
(my/load-module "org/org-timegrid")

;; texpresso-view: inert until a patched TeXpresso checkout exists (#8)
(my/load-module "org/texpresso-view")

;; --- markdown ---
(my/load-module "markdown/markdown-mode")
;; d2 / mermaid / plantuml / graphviz for md and org blocks (#2)
(my/load-module "markdown/diagrams")

;; --- workspaces ---
;; space-tree replaces persp-mode (#15); bookmark-view persists views and
;; agent-shell-links keeps agent sessions reachable without autosaved sessions.
(my/load-module "projects/space-tree")
(my/load-module "projects/bookmark-view")
(my/load-module "projects/agent-shell-links")
;; Indentation guides for elisp (#9)
(my/load-module "projects/tree-guide")

;; --- pdf ---
(my/load-module "pdf/pdf-tools")

;; --- themes ---
(my/load-module "themes/modus-themes")
(my/load-module "themes/doom-themes")
(my/load-module "themes/nerd-icons")
(my/load-module "themes/doom-modeline")
(my/load-module "themes/fonts")

;; --- custom helpers ---
(my/load-module "custom/helpers")

;; --- startup summary ---
;; Modules are loaded in isolation, so report anything that broke instead of
;; leaving a silently half-configured Emacs.
(when my/failed-modules
  (message "Emacs startup: %d module(s) failed to load: %s"
           (length my/failed-modules)
           (mapconcat #'car (reverse my/failed-modules) ", ")))
