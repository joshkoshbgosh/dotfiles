;; -*- lexical-binding: t -*-
;;; init.el — Emacs config manifest
;; All config lives in individual files under these directories.
;; Load order matters (dependencies first).

(defun my/load-module (path)
  "Load a module file from config directory without errors."
  (let ((config-root (file-name-directory
                       (file-truename (or user-init-file load-file-name buffer-file-name)))))
    (load (expand-file-name (concat path ".el") config-root)
          nil t t)))

;; --- startup ---
(my/load-module "startup/straight")
(my/load-module "startup/paths")
(my/load-module "startup/treesit")

;; --- core ---
(my/load-module "core/emacs")
(my/load-module "core/which-key")
(my/load-module "core/discover")
(my/load-module "core/transient")

;; --- editing ---
(my/load-module "evil/undo-fu")
(my/load-module "evil/evil")
(my/load-module "evil/evil-collection")
(my/load-module "evil/evil-commentary")

;; --- tabs & appearance ---
(my/load-module "tabs/centaur-tabs")
(my/load-module "appearance/dimmer")
(my/load-module "appearance/ui")

;; --- leader keys ---
(my/load-module "leader/general")

;; --- completion ---
(my/load-module "completion/vertico")
(my/load-module "completion/vertico-posframe")
(my/load-module "completion/orderless")
(my/load-module "completion/marginalia")
(my/load-module "completion/consult")
(my/load-module "completion/consult-dir")
(my/load-module "completion/embark")
(my/load-module "completion/embark-consult")

;; --- projects ---
(my/load-module "projects/project")
(my/load-module "projects/persp-mode")

;; --- git ---
(my/load-module "git/magit")
(my/load-module "git/magit-todos")
(my/load-module "git/diff-hl")

;; --- file explorer ---
(my/load-module "files/dirvish")

;; --- terminal ---
(my/load-module "terminal/vterm")
(my/load-module "terminal/ghostel")
(my/load-module "terminal/eat")

;; --- agents ---
(my/load-module "agents/agent-shell-notifications")
(my/load-module "agents/knockknock")
(my/load-module "agents/agent-shell-manager")
(my/load-module "agents/agent-review")
(my/load-module "agents/meta-agent-shell")
(my/load-module "agents/agent-shell-knockknock")
(my/load-module "agents/agent-shell")

;; --- lsp ---
(my/load-module "lsp/corfu")
(my/load-module "lsp/cape")
(my/load-module "lsp/eglot")

;; --- org ---
(my/load-module "org/org")
(my/load-module "org/org-modern")
(my/load-module "org/org-appear")
(my/load-module "org/org-roam")
(my/load-module "org/supertag")
(my/load-module "org/org-ql")
(my/load-module "org/org-super-agenda")
(my/load-module "org/org-wild-notifier")
(my/load-module "org/org-tidy")
(my/load-module "org/org-sticky-header")
(my/load-module "org/org-agenda-property")
(my/load-module "org/org-pomodoro")
(my/load-module "org/org-sidebar")
(my/load-module "org/calfw")
(my/load-module "org/calfw-org")
(my/load-module "org/org-time-budgets")
(my/load-module "org/openspec")

;; --- markdown ---
(my/load-module "markdown/markdown-mode")

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