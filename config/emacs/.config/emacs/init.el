;;; init.el --- Josh's Emacs config -*- lexical-binding: t; -*-

;; ------------------------------
;; Restore saner GC after startup
;; ------------------------------
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 32 1024 1024)
                  gc-cons-percentage 0.2)))


;; ------------------------------
;; straight.el bootstrap
;; ------------------------------
(defvar bootstrap-version)
(let* ((straight-dir (expand-file-name "straight/" user-emacs-directory))
       (bootstrap-file (expand-file-name "repos/straight.el/bootstrap.el" straight-dir))
       (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)
(setq straight-use-package-by-default t
      use-package-always-defer t)

;; Lockfile helpers
(defun my/straight-freeze ()
  "Write lockfile for current straight package set."
  (interactive)
  (straight-freeze-versions))

(defun my/straight-thaw ()
  "Re-pin packages to lockfile + sync."
  (interactive)
  (straight-thaw-versions)
  (straight-pull-all)
  (straight-check-all))

;; ------------------------------
;; Core QoL
;; ------------------------------
(use-package emacs
  :init
  (setq ring-bell-function 'ignore
        make-backup-files nil
        auto-save-default nil
        create-lockfiles nil
        scroll-conservatively 101
        scroll-margin 5
        use-short-answers t
        confirm-kill-emacs 'y-or-n-p)
  :config
  (save-place-mode 1)
  (savehist-mode 1)
  (recentf-mode 1))

;; ------------------------------
;; which-key: discoverability
;; ------------------------------
(use-package which-key
  :demand t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.4))

;; ------------------------------
;; Evil (vim) + collections
;; ------------------------------
(use-package undo-fu)

(use-package evil
  :demand t
  :init
  (setq evil-want-keybinding nil
        evil-want-integration t
        evil-respect-visual-line-mode t
        evil-undo-system 'undo-fu)
  :config
  (evil-mode 1))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

;; ------------------------------
;; Leader keys (SPC) via general
;; ------------------------------
(use-package general
  :after evil
  :config
  (general-create-definer my/leader
    :states '(normal visual motion)
    :keymaps 'override
    :prefix "SPC"
    :global-prefix "C-SPC")

  ;; A tiny "Doom-ish" starter map (we’ll evolve this)
  (my/leader
    "SPC" '(execute-extended-command :which-key "M-x")
    "f"   '(:ignore t :which-key "files")
    "f f" '(find-file :which-key "find file")
    "f r" '(recentf-open-files :which-key "recent files")
    "b"   '(:ignore t :which-key "buffers")
    "b b" '(consult-buffer :which-key "switch buffer")
    "b k" '(kill-current-buffer :which-key "kill buffer")
    "w"   '(:ignore t :which-key "windows")
    "w /" '(split-window-right :which-key "split right")
    "w -" '(split-window-below :which-key "split below")
    "w d" '(delete-window :which-key "delete window")))

;; ------------------------------
;; Completion / search stack (fast “telescope-like”)
;; ------------------------------
(use-package vertico
  :demand t
  :config (vertico-mode 1))

(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :after vertico
  :config (marginalia-mode 1))

(use-package consult
  :after vertico
  :init
  (setq consult-preview-key "M-.")
  :config
  (my/leader
    "s"   '(:ignore t :which-key "search")
    "s r" '(consult-ripgrep :which-key "ripgrep")
    "s l" '(consult-line :which-key "line")
    "t"   '(:ignore t :which-key "toggles")
    "t t" '(consult-theme :which-key "choose theme")))

(with-eval-after-load 'consult
  (my/leader
    "p s" '(consult-ripgrep :which-key "ripgrep (project)")))

(use-package embark
  :bind (("C-." . embark-act)))

;; ------------------------------
;; Projects + Workspaces + Session restore
;; ------------------------------
(use-package project
  :straight (:type built-in)
  :demand t
  :init
  (setq project-list-file (expand-file-name "projects.eld" user-emacs-directory)
        project-search-path (list (expand-file-name "~/Work")))
  :config
  (my/leader
    "p"   '(:ignore t :which-key "project")
    "p p" '(project-switch-project :which-key "switch project")
    "p f" '(project-find-file :which-key "find file")
    "p b" '(project-switch-to-buffer :which-key "switch buffer")
    "p d" '(project-find-dir :which-key "find dir")
    "p !" '(project-shell-command :which-key "shell command")
    "p c" '(project-compile :which-key "compile")))

(use-package persp-mode
  :demand t
  :init
  (setq persp-autosave-mode t
        persp-save-dir (expand-file-name "persp/" user-emacs-directory))
  :config
  (persp-mode 1)
  (my/leader
    "TAB" '(:ignore t :which-key "workspace")
    "TAB TAB" '(persp-switch :which-key "switch")
    "TAB n"   '(persp-next :which-key "next")
    "TAB p"   '(persp-prev :which-key "prev")
    "TAB k"   '(persp-kill :which-key "kill")))

(defun my/workspace-switch-to-project ()
  "Pick a directory, treat it as a project, switch to a workspace for it."
  (interactive)
  (let* ((dir (read-directory-name "Project dir: " (expand-file-name "~/Work/") nil t))
         (dir (file-name-as-directory (expand-file-name dir)))
         (name (file-name-nondirectory (directory-file-name dir)))
         (proj (project-current nil dir)))
    ;; Only remember if project.el can detect a real project (e.g., git repo).
    (when proj
      (project-remember-project proj))
    (persp-switch name)
    (dired dir)))

(defun my/workspace-project-magit ()
  "Project -> workspace -> magit-status."
  (interactive)
  (let* ((dir (project-prompt-project-dir))
         (name (file-name-nondirectory (directory-file-name dir))))
    (persp-switch name)
    (magit-status dir)))

(with-eval-after-load 'general
  (my/leader
    "p P" '(my/workspace-switch-to-project :which-key "project -> workspace")
    "p G" '(my/workspace-project-magit :which-key "project -> workspace -> magit")))

;; Optional extra session restore (buffers/windows). persp already helps a lot.
(setq desktop-path (list user-emacs-directory)
      desktop-save t)
(desktop-save-mode 1)

;; ------------------------------
;; File tree
;; ------------------------------
(use-package treemacs
  :config
  (setq treemacs-width 34)
  (my/leader "e" '(treemacs :which-key "file tree")))

(use-package treemacs-evil :after (treemacs evil))

(defun my/project-root ()
  "Return current project root, or nil if not in a project."
  (when-let ((proj (project-current nil)))
    (project-root proj)))

(defun my/treemacs-open-current-project ()
  "Open (or focus) Treemacs rooted at the current project."
  (interactive)
  (let ((root (or (my/project-root)
                  (read-directory-name "Project root: "))))
    (treemacs)
    ;; Ensure Treemacs is showing ROOT
    (treemacs-add-and-display-current-project-exclusively)))

;; The helper treemacs uses for “current project” is project.el-aware
(setq treemacs-project-follow-cleanup t)

(with-eval-after-load 'general
  (my/leader
    "p e" '(my/treemacs-open-current-project :which-key "treemacs (project)")
    "e"   '(treemacs :which-key "file tree")))

;; ------------------------------
;; Terminal inside Emacs
;; ------------------------------
(use-package vterm
  :commands vterm
  :config
  (my/leader
    "o"   '(:ignore t :which-key "open")
    "o t" '(vterm :which-key "vterm")))

;; ------------------------------
;; LSP (Eglot) + Completion UI (Corfu)
;; ------------------------------
(use-package corfu
  :demand t
  :init
  (setq corfu-auto t
        corfu-cycle t
        corfu-preview-current nil)
  :config
  (global-corfu-mode 1))

(use-package cape
  :after corfu
  :init
  ;; Add useful completion-at-point sources
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev))

(use-package eglot
  :commands (eglot eglot-ensure)
  :init
  ;; Auto-start LSP for programming modes
  (add-hook 'prog-mode-hook #'eglot-ensure)
  :config
  (setq eglot-autoshutdown t
        eglot-send-changes-idle-time 0.2)
  (my/leader
    "c"   '(:ignore t :which-key "code")
    "c a" '(eglot-code-actions :which-key "code actions")
    "c r" '(eglot-rename :which-key "rename")
    "c f" '(eglot-format :which-key "format")
    "c d" '(xref-find-definitions :which-key "definition")
    "c R" '(xref-find-references :which-key "references")))

;; ------------------------------
;; Org: second brain + literate programming
;; ------------------------------
(use-package org
  :straight (:type built-in)
  :init
  (setq org-directory (expand-file-name "~/org/")
        org-hide-emphasis-markers t
        org-startup-indented t
        org-ellipsis " ▾"
        org-log-done 'time
        org-src-tab-acts-natively t
        org-confirm-babel-evaluate nil)
  :config
  ;; Babel languages (extend as needed)
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (python . t)
     (shell . t))))

(defun my/org-today-file ()
  "Return path to today's daily note file."
  (expand-file-name (format-time-string "daily/%Y-%m-%d.org") org-directory))

(defun my/org-open-today ()
  "Open today's daily note."
  (interactive)
  (find-file (my/org-today-file)))

(with-eval-after-load 'org
  (setq org-default-notes-file (expand-file-name "inbox.org" org-directory)
        org-agenda-files (list org-directory))

  (setq org-capture-templates
        `(("t" "Task (inbox)" entry
           (file ,org-default-notes-file)
           "* TODO %?\n  %U\n  %a\n")
          ("n" "Note (inbox)" entry
           (file ,org-default-notes-file)
           "* %?\n  %U\n  %a\n")
          ("j" "Journal (today)" entry
           (file+olp+datetree ,(expand-file-name "journal.org" org-directory))
           "* %?\n%U\n")))

  (my/leader
    "n c" '(org-capture :which-key "capture")
    "n a" '(org-agenda :which-key "agenda")
    "n t" '(my/org-open-today :which-key "today")))

(use-package org-modern
  :after org
  :config (global-org-modern-mode 1))

(use-package org-appear
  :after org
  :hook (org-mode . org-appear-mode))

(use-package org-roam
  :after org
  :init
  (setq org-roam-directory (file-truename (expand-file-name "roam/" org-directory)))
  :config
  (org-roam-db-autosync-mode 1)
  (my/leader
    "n"   '(:ignore t :which-key "notes")
    "n f" '(org-roam-node-find :which-key "find node")
    "n i" '(org-roam-node-insert :which-key "insert link")
    "n g" '(org-roam-graph :which-key "graph")))

;; ------------------------------
;; Themes / Fonts
;; ------------------------------
(setq-default line-spacing 0.0)

(defun my/font-set (family height)
  "Set default font FAMILY at HEIGHT (1/10 pt)."
  (set-face-attribute 'default nil :family family :height height))

(defun my/font-bigger ()
  (interactive)
  (set-face-attribute 'default nil :height (+ (face-attribute 'default :height) 10)))

(defun my/font-smaller ()
  (interactive)
  (set-face-attribute 'default nil :height (- (face-attribute 'default :height) 10)))

(with-eval-after-load 'general
  (my/leader
    "t f"  '(set-frame-font :which-key "set font (prompt)")
    "t +"  '(my/font-bigger :which-key "font bigger")
    "t -"  '(my/font-smaller :which-key "font smaller")))

;; Bigger text + more breathing room
(set-face-attribute 'default nil :family "JetBrains Mono" :height 160) ; 16pt-ish
(setq-default line-spacing 0.15)
(set-fringe-mode 16)

;; Make UI elements easier to see
(global-hl-line-mode 1)
(setq-default cursor-type 'bar)

(defun my/disable-all-themes ()
  "Disable all enabled themes."
  (interactive)
  (mapc #'disable-theme custom-enabled-themes))

(use-package modus-themes
  :straight (:type built-in)
  :init
  ;; High contrast defaults
  (setq modus-themes-bold-constructs t
        modus-themes-italic-constructs t
        modus-themes-mixed-fonts t
        modus-themes-prompts '(bold intense))
  )

(use-package doom-themes
  :demand t
  :config
  (my/disable-all-themes)     ;; optional but avoids theme stacking
  (load-theme 'doom-one t))

(use-package nerd-icons)
(use-package doom-modeline
  :init
  (setq doom-modeline-height 34)
  :config
  (doom-modeline-mode 1))


(with-eval-after-load 'general
  (my/leader
    "t 0" '(my/disable-all-themes :which-key "disable themes")))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   '("aec7b55f2a13307a55517fdf08438863d694550565dee23181d2ebd973ebd6b8"
     "0325a6b5eea7e5febae709dab35ec8648908af12cf2d2b569bedc8da0a3a81c1"
     default)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
