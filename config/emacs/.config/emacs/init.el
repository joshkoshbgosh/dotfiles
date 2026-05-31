;;;  startup
;; ------------------------------
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 32 1024 1024)
                  gc-cons-percentage 0.2)))

;; Fix for Wayland resize issues in native GUI Emacs frames
(setq inhibit-compacting-font-caches t)

;; NOTE: redraw-display on window-configuration-change-hook removed —
;; it caused a redisplay feedback loop with dirvish preview windows,
;; producing constant "wrong-type-argument number-or-marker-p nil" errors
;; and severe navigation lag.

;; Emacs 30.2 + libtree-sitter >= 0.25 are mutually incompatible on predicates:
;; libtree-sitter now requires a `?' suffix (`#match?'), but Emacs's C-side
;; serializer/runtime still uses the bare form (`#match').  Neither end accepts
;; the other's spelling, and there's no in-Lisp way to bridge them.  As a
;; degraded workaround, strip top-level patterns that use :match/:equal/:pred
;; before compiling.  Built-in modes that use these (typescript-ts-mode's
;; `constant' / `number' features) always pair the predicate-bearing pattern
;; with non-predicate alternatives, so other highlighting still works; only
;; the predicate-gated cases (e.g. ALL_CAPS-as-constant, NaN/Infinity) are lost.
;; Must run before any package (e.g. persp-mode) restores .ts/.tsx buffers,
;; which would otherwise compile and cache the broken queries.
(require 'cl-lib)
(defun my/treesit-pattern-has-predicate-p (form)
  (cond ((memq form '(:match :equal :pred)) t)
        ((consp form)
         (or (my/treesit-pattern-has-predicate-p (car form))
             (my/treesit-pattern-has-predicate-p (cdr form))))))
(define-advice treesit-query-compile
    (:around (orig lang query &optional eager) my/strip-broken-predicates)
  (let ((q query))
    (when (and (consp q) (not (stringp q)))
      (let ((cleaned (cl-remove-if #'my/treesit-pattern-has-predicate-p q)))
        (when cleaned (setq q cleaned))))
    (funcall orig lang q eager)))


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

(defun my/switch-theme (theme)
  "Disable all active themes then load THEME cleanly."
  (interactive
   (list (intern (completing-read "Load theme: "
                                  (mapcar #'symbol-name (custom-available-themes))))))
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t))

;; ------------------------------
;; Machine-specific paths
;; ------------------------------
(defvar my/workspace-dirs '("~/Workspace/" "~/Work/")
  "Candidate workspace roots across machines.")

(defun my/first-existing-dir (dirs)
  "Return the first existing directory from DIRS, or nil."
  (seq-find #'file-directory-p dirs))

(defvar my/current-workspace-dir
  (or (my/first-existing-dir my/workspace-dirs)
      "~/Workspace/")
  "Workspace root for the current machine.")

(defvar my/lifeos-dir
  (or (my/first-existing-dir
       (mapcar (lambda (dir)
                 (expand-file-name "lifeos/" dir))
               my/workspace-dirs))
      (expand-file-name "lifeos/" my/current-workspace-dir))
  "LifeOS root for the current machine.")

(defvar my/config-root-dir
  (file-name-directory
   (file-truename (or user-init-file load-file-name buffer-file-name)))
  "Directory containing this Emacs config.")

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
        use-dialog-box nil            ; never pop GTK dialogs, always use minibuffer
        confirm-kill-emacs 'y-or-n-p)
  :config
  (save-place-mode 1)
  (savehist-mode 1)
  (recentf-mode 1)
  ;; Auto-revert buffers when files change on disk
  (global-auto-revert-mode 1)
  (setq auto-revert-interval 1
        auto-revert-check-vc-info t
        global-auto-revert-non-file-buffers t)
  ;; Auto-save the actual file after idle (not #temp# files)
  ;; save-silently suppresses the "Saving..." echo; auto-revert handles disk conflicts
  (setq auto-save-visited-interval 2
        save-silently t)
  (auto-save-visited-mode 1)
  ;; Ediff: use plain layout and always start from a non-side window.
  ;; Side windows (like claude-code-ide) are not splittable; ediff calls
  ;; split-window both on startup and when showing help (?), so we must
  ;; redirect focus to a regular window before ediff touches the layout.
  (setq ediff-window-setup-function #'ediff-setup-windows-plain
        ediff-split-window-function #'split-window-horizontally)
  (defun my/ediff-select-non-side-window (&rest _)
    (when-let ((win (seq-find (lambda (w) (not (window-parameter w 'window-side)))
                              (window-list))))
      (select-window win)))
  (advice-add 'ediff-setup-windows-plain :before #'my/ediff-select-non-side-window)
  ;; Enable Emacs server for MCP integration
  (server-start)
  ;; Line numbers: absolute current, relative others
  (setq display-line-numbers-type 'relative
        display-line-numbers-current-absolute t)
  (global-display-line-numbers-mode 1))

;; ------------------------------
;; which-key: discoverability
;; ------------------------------
(use-package which-key
  :demand t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.25
        which-key-idle-secondary-delay 0.05
        which-key-sort-order 'which-key-key-order
        which-key-show-remaining-keys t))

(use-package discover-my-major
  :commands (discover-my-major))

(use-package transient
  :straight (:type built-in)
  :demand t)

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

(use-package evil-commentary
  :after evil
  :config (evil-commentary-mode 1))

;; ------------------------------
;; Tabs (centaur-tabs) — LazyVim-style buffer tabs
;; ------------------------------
(use-package centaur-tabs
  :demand t
  :init
  (setq centaur-tabs-style "bar"
        centaur-tabs-height 32
        centaur-tabs-set-icons t
        centaur-tabs-icon-type 'nerd-icons
        centaur-tabs-set-modified-marker t
        centaur-tabs-modified-marker "●"
        centaur-tabs-close-button "✕"
        centaur-tabs-set-bar 'under
        centaur-tabs-show-new-tab-button nil
        centaur-tabs-set-close-button t)
  :config
  (centaur-tabs-mode 1)
  ;; Group tabs by project.el
  (defun my/centaur-tabs-project-group ()
    "Group tabs by project.el root."
    (list (let ((proj (project-current)))
            (if proj
                (file-name-nondirectory (directory-file-name (project-root proj)))
              "Other"))))
  (setq centaur-tabs-buffer-groups-function #'my/centaur-tabs-project-group)
  ;; Only show file-visiting buffers; exclude special/terminal buffers
  (defun my/centaur-tabs-buffer-list ()
    "Return buffers to show as tabs — exclude special and terminal buffers."
    (seq-filter
     (lambda (b)
       (let ((name (buffer-name b)))
         (and (not (string-prefix-p "*" name))
              (not (string-prefix-p " " name))
              (not (with-current-buffer b
                     (derived-mode-p 'vterm-mode 'magit-mode 'dired-mode))))))
     (buffer-list)))
  (setq centaur-tabs-buffer-list-function #'my/centaur-tabs-buffer-list)
  ;; Cycle only within visible tabs (wrap around, don't jump to other windows)
  (setq centaur-tabs-cycle-scope 'tabs)
  ;; Color tab text based on git vc-state (matches diff-hl fringe colors)
  (setq centaur-tabs-buffer-face-function
        (lambda (buf)
          (with-current-buffer buf
            (when (and buffer-file-name
                       (vc-registered buffer-file-name))
              (pcase (vc-state buffer-file-name)
                ('edited  'diff-hl-change)
                ('added   'diff-hl-insert)
                ('removed 'diff-hl-delete)
                (_         nil)))))))

;; ------------------------------
;; Window visibility: dim inactive windows
;; ------------------------------
(use-package dimmer
  :demand t
  :config
  (dimmer-mode 1)
  (setq dimmer-fraction 0.15))

;; ------------------------------
;; Leader keys (M-;) via general
;; ------------------------------
(use-package general
  :after evil
  :config
  (general-create-definer my/leader
    :states '(normal visual motion emacs)
    :keymaps 'override
    :prefix "M-;"
    :global-prefix "C-M-;")

  (my/leader
    ";" '(execute-extended-command :which-key "M-x")
    "f"   '(:ignore t :which-key "files")
    "f f" '(my/find-file-prompt :which-key "find file")
    "f r" '(recentf-open-files :which-key "recent files")
    "b"   '(:ignore t :which-key "buffers")
    "b b" '(consult-buffer :which-key "switch buffer")
    "b d" '(kill-current-buffer :which-key "kill buffer")
    "b D" '(centaur-tabs-kill-other-buffers-in-current-group :which-key "kill other buffers in group")
    "b n" '(centaur-tabs-forward :which-key "next tab")
    "b p" '(centaur-tabs-backward :which-key "prev tab")
    "w"   '(:ignore t :which-key "windows")
    "w /" '(split-window-right :which-key "split right")
    "w -" '(split-window-below :which-key "split below")
    "w d" '(delete-window :which-key "delete window")
    ;; Registered eagerly — packages load lazily but bindings must exist at startup
    "s"   '(:ignore t :which-key "search")
    "s r" '(consult-ripgrep :which-key "ripgrep")
    "s l" '(consult-line :which-key "line")
    "s f" '(consult-find :which-key "find file")
    "s o" '(consult-outline :which-key "outline")
    "s i" '(consult-imenu :which-key "imenu")
    "s d" '(consult-dir :which-key "directory")
    "/"   '(consult-ripgrep :which-key "search project")
    "t"   '(:ignore t :which-key "toggles")
    "t t" '(consult-theme :which-key "choose theme")
    "c"   '(:ignore t :which-key "code")
    "c a" '(eglot-code-actions :which-key "code actions")
    "c r" '(eglot-rename :which-key "rename")
    "c f" '(eglot-format :which-key "format")
    "c d" '(xref-find-definitions :which-key "definition")
    "c R" '(xref-find-references :which-key "references")
    "c k" '(eldoc-doc-buffer :which-key "hover / type info")
    "c n" '(flymake-goto-next-error :which-key "next error")
    "c p" '(flymake-goto-prev-error :which-key "prev error")
    "c e" '(consult-flymake :which-key "error list")
    "c D" '(flymake-show-buffer-diagnostics :which-key "diagnostics buffer")
    "c i" '(eglot-find-implementation :which-key "implementation")
    "n"   '(:ignore t :which-key "notes")
    "n c" '(org-capture :which-key "capture")
    "n a" '(org-agenda :which-key "agenda")
    "n d" '(my/lifeos-open-dashboard :which-key "dashboard")
    "n t" '(my/org-open-today :which-key "today")
    "n h" '(my/lifeos-open-habits :which-key "habits")
    "n r" '(my/lifeos-open-reviews :which-key "reviews")
    "n f" '(org-roam-node-find :which-key "find node")
    "n i" '(org-roam-node-insert :which-key "insert link")
    "n g" '(org-roam-graph :which-key "graph")
    "n p"   '(:ignore t :which-key "project")
    "n s" '(org-sidebar :which-key "sidebar")
    "n S" '(org-sidebar-tree :which-key "sidebar tree")
    "n P" '(org-pomodoro :which-key "pomodoro")
    "o"   '(:ignore t :which-key "open")
    "o t" '(vterm :which-key "vterm"))

  ;; M-hjkl window navigation (works in all evil states and emacs state)
  (general-define-key
    :keymaps 'override
    "M-h" #'windmove-left
    "M-j" #'windmove-down
    "M-k" #'windmove-up
    "M-l" #'windmove-right)

  ;; H/L for tab switching in normal mode (LazyVim-style)
  (general-define-key
    :states '(normal)
    :keymaps 'override
    "H" #'centaur-tabs-backward
    "L" #'centaur-tabs-forward))

;; Find-file prompt: window or tab
(defun my/find-file-prompt ()
  "Find file, asking whether to open in a new window or current tab."
  (interactive)
  (let* ((file (read-file-name "Find file: "))
         (choice (read-char-choice "[w]indow / [t]ab: " '(?w ?t))))
    (pcase choice
      (?w (find-file-other-window file))
      (?t (find-file file)))))

;; ------------------------------
;; Completion / search stack (fast "telescope-like")
;; ------------------------------
(use-package vertico
  :demand t
  :config (vertico-mode 1))

(use-package vertico-posframe
  :after vertico
  :config
  (setq vertico-posframe-parameters
        '((left-fringe . 8)
          (right-fringe . 8))
        vertico-posframe-poshandler #'posframe-poshandler-frame-center
        vertico-posframe-width 100)
  (vertico-posframe-mode 1))

(defun my/toggle-vertico-posframe ()
  "Toggle vertico-posframe on/off (escape hatch for Wayland issues)."
  (interactive)
  (if vertico-posframe-mode
      (vertico-posframe-mode -1)
    (vertico-posframe-mode 1)))

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
  ;; Auto-preview with debounce (Telescope-like behavior)
  (setq consult-preview-key '(:debounce 0.2 any)))

(with-eval-after-load 'consult
  (my/leader
    "p s" '(consult-ripgrep :which-key "ripgrep (project)")))

(use-package consult-dir
  :after (consult vertico)
  :bind (("C-x C-d" . consult-dir)
         :map vertico-map
         ("C-x C-d" . consult-dir)
         ("C-x C-j" . consult-dir-jump-file)))

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim))
  :init
  (setq embark-indicators
        '(embark-which-key-indicator
          embark-highlight-indicator
          embark-isearch-highlight-indicator))
  :config
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none))))
  ;; Add magit-status action for files/directories
  (define-key embark-file-map (kbd "g") #'magit-status))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; ------------------------------
;; Projects + Workspaces + Session restore
;; ------------------------------
(use-package project
  :straight (:type built-in)
  :demand t
  :init
  (setq project-list-file (expand-file-name "projects.eld" user-emacs-directory)
        project-search-path (list (expand-file-name my/current-workspace-dir)))
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
        persp-auto-resume-time 0
        persp-save-window-conf t
        persp-save-dir (expand-file-name "persp/" user-emacs-directory))
  :config
  (persp-mode 1)
  ;; Load saved perspectives if they exist
  (let ((state-file (expand-file-name "persp-auto-save" persp-save-dir)))
    (when (file-exists-p state-file)
      (condition-case nil
          (persp-load-state-from-file state-file)
        (error (message "Warning: Could not restore persp-mode state")))))
  (my/leader
    "TAB" '(:ignore t :which-key "workspace")
    "TAB TAB" '(persp-switch :which-key "switch")
    "TAB n"   '(persp-next :which-key "next")
    "TAB p"   '(persp-prev :which-key "prev")
    "TAB k"   '(persp-kill :which-key "kill")))

(defun my/workspace-switch-to-project ()
  "Pick a directory, treat it as a project, switch to a workspace for it."
  (interactive)
  (let* ((dir (read-directory-name "Project dir: " my/current-workspace-dir nil t))
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

;; Desktop save disabled - using persp-mode instead for workspace restoration
;; (setq desktop-path (list user-emacs-directory)
;;       desktop-save t)
;; (desktop-save-mode 1)

;; ------------------------------
;; Git (Magit + magit-todos)
;; ------------------------------
(use-package magit
  :commands (magit-status magit-log-current magit-log-all
             magit-blame magit-diff-dwim magit-file-dispatch
             magit-stage-file magit-unstage-file)
  :config
  (setq magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))

(use-package magit-todos
  :after magit
  :config (magit-todos-mode 1))

(with-eval-after-load 'general
  (my/leader
    "g"   '(:ignore t :which-key "git")
    "g g" '(magit-status :which-key "status")
    "g l" '(magit-log-current :which-key "log (current)")
    "g L" '(magit-log-all :which-key "log (all)")
    "g b" '(magit-blame :which-key "blame")
    "g d" '(magit-diff-dwim :which-key "diff")
    "g f" '(magit-file-dispatch :which-key "file dispatch")
    "g s" '(magit-stage-file :which-key "stage file")
    "g u" '(magit-unstage-file :which-key "unstage file")
    "g D" '(diff-hl-show-hunk :which-key "show diff hunk")
    "g t" '(diff-hl-mode :which-key "toggle diff-hl")))

;; ------------------------------
;; Git fringe indicators (diff-hl)
;; ------------------------------
(use-package diff-hl
  :demand t
  :config
  (global-diff-hl-mode 1)
  (diff-hl-flydiff-mode 1)       ; show unstaged changes without saving
  (add-hook 'dired-mode-hook #'diff-hl-dired-mode-unless-remote) ; fringe indicators in dired
  ;; Keep in sync with magit operations
  (add-hook 'magit-pre-refresh-hook  #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)
  ;; Auto-update after external commits (e.g., from Claude Code / terminal).
  ;; vc-refresh-state fires periodically via auto-revert-check-vc-info.
  (advice-add 'vc-refresh-state :after
              (lambda (&rest _)
                (when (bound-and-true-p diff-hl-mode)
                  (diff-hl-update-once)))))

;; ------------------------------
;; File explorer (Dired + Dirvish)
;; ------------------------------
(use-package dirvish
  :demand t
  :init
  ;; Work around a known native-comp warning in dirvish-extras.el.
  (when (boundp 'native-comp-jit-compilation-deny-list)
    (add-to-list 'native-comp-jit-compilation-deny-list "dirvish-extras\\.el\\'"))
  ;; Keep dired-native workflow; enhance UI with Dirvish.
  (dirvish-override-dired-mode 1)
  :config
  ;; Full-frame dirvish with rich attributes
  ;; git-msg removed: spawns a git subprocess per file causing lag + display errors
  (setq dirvish-attributes '(subtree-state nerd-icon vc-state file-size collapse))

  ;; Quick access entries
  (setq dirvish-quick-access-entries
        `(("w" ,my/current-workspace-dir     ,(directory-file-name
                                                (file-name-nondirectory
                                                 (directory-file-name my/current-workspace-dir))))
          ("o" "~/org/"                     "Org")
          ("h" "~/"                         "Home")
          ("d" "~/Downloads/"               "Downloads")
          ("e" ,user-emacs-directory        "Emacs config")))

  ;; Debounce preview so rapid j/k navigation doesn't stall on each file.
  ;; Without this, every cursor movement triggers a synchronous preview
  ;; render (or async subprocess spawn), causing visible lag.
  (setq dirvish-preview-delay 0.1)

  ;; Use Poppler's absolute paths for PDF thumbnails/metadata so Dirvish preview
  ;; works reliably even if PATH differs between shells and GUI Emacs.
  (setq dirvish-pdftoppm-program (or (executable-find "pdftoppm") "pdftoppm")
        dirvish-pdfinfo-program (or (executable-find "pdfinfo") "pdfinfo"))

  ;; Don't try to preview large files synchronously
  (setq dirvish-preview-large-file-threshold (* 5 1024 1024))

  ;; Skip preview for binary/media formats that can't be rendered usefully
  (setq dirvish-preview-disabled-exts
        '("iso" "bin" "exe" "dll" "so" "dmg" "mp4" "mkv" "avi" "mov" "zip" "tar" "gz" "7z"))

  ;; Guard dirvish--redisplay (added to pre-redisplay-functions) against nil
  ;; sessions. Without this, navigating in dirvish throws:
  ;;   "redisplay--pre-redisplay-functions: (wrong-type-argument number-or-marker-p nil)"
  (define-advice dirvish--redisplay (:around (fn &rest args) safe-guard)
    "Catch wrong-type-argument when dirvish session/position is nil."
    (condition-case nil
      (apply fn args)
      (wrong-type-argument nil)))

  ;; Also guard the async preview sentinel against stale sessions.
  (with-eval-after-load 'dirvish-preview
    (defun my/dirvish--sentinel-safe (proc _event)
      "Safe wrapper for `dirvish--preview-update' in process sentinels."
      (when (and (processp proc) (process-buffer proc))
        (ignore-errors
          (dirvish--preview-update (process-get proc 'dv)))))
    (advice-add 'dirvish--sentinel :override #'my/dirvish--sentinel-safe))

  ;; Load extensions
  (require 'dirvish-subtree)
  (require 'dirvish-yank)
  (require 'dirvish-quick-access)
  (require 'dirvish-vc)
  (require 'dirvish-peek)
  (require 'dirvish-history)
  (require 'dirvish-collapse)

  ;; Peek mode for minibuffer previews
  (dirvish-peek-mode 1)

  ;; No line numbers in dired/dirvish
  (add-hook 'dired-mode-hook (lambda () (display-line-numbers-mode -1)))

  ;; Help segment for dirvish mode-line
  (dirvish-define-mode-line my-help
    "Compact key hints."
    (propertize " j/k move  h/- up  l open  m/u/t marks  C copy  R rename  D delete  g refresh  SPC ? shortcuts "
                'face 'shadow))
  (setq dirvish-mode-line-format '(:left (my-help) :right (sort symlink)))

  ;; Evil keybindings for dired navigation
  (with-eval-after-load 'evil
    (define-key dired-mode-map [remap evil-forward-char] #'dired-find-file)
    (define-key dired-mode-map [remap evil-backward-char] #'dired-up-directory)
    (define-key dired-mode-map [remap evil-previous-line-first-non-blank] #'dired-up-directory)))

(defun my/discover-current-mode ()
  "Show discoverability help for current major mode."
  (interactive)
  (if (fboundp 'discover-my-major)
      (discover-my-major)
    (describe-mode)))

(defun my/project-root ()
  "Return current project root, or nil if not in a project.
   Uses perspective name, buffers, or current directory to detect project."
  (let ((persp (get-current-persp)))
    (or
     ;; 1. Try perspective name matching project directories (only if in a named perspective)
     (when (and persp
                (not (string= (persp-name persp) "none"))
                (not (string= (persp-name persp) "main")))
       (let* ((persp-name (persp-name persp))
              (proj-dir (expand-file-name persp-name my/current-workspace-dir))
              (git-dir (expand-file-name ".git" proj-dir)))
         (when (file-directory-p git-dir)
           proj-dir)))
     ;; 2. Try project detection from current buffer
     (when-let ((proj (project-current nil)))
       (project-root proj))
     ;; 3. Try finding project from default-directory
     (when-let ((proj (project-current nil default-directory)))
       (project-root proj)))))

(defun my/dirvish-project ()
  "Open dirvish (full-frame) at the current project root."
  (interactive)
  (let ((root (or (my/project-root) default-directory)))
    (dirvish root)))

(with-eval-after-load 'general
  (my/leader
    "?"   '(which-key-show-top-level :which-key "shortcut discovery")
    "h"   '(:ignore t :which-key "help")
    "h m" '(my/discover-current-mode :which-key "mode commands")
    "h k" '(describe-key :which-key "describe key")
    "h f" '(describe-function :which-key "describe function")
    "h v" '(describe-variable :which-key "describe variable")
    "e"   '(my/dirvish-project :which-key "explorer (full)")
    "E"   '(dirvish-quick-access :which-key "quick access dirs")))

;; ------------------------------
;; PDF viewing
;; ------------------------------
(use-package pdf-tools
  :mode (("\\.pdf\\'" . pdf-view-mode))
  :config
  (pdf-loader-install)
  (setq-default pdf-view-display-size 'fit-width)
  (add-hook 'pdf-view-mode-hook
            (lambda ()
              (display-line-numbers-mode -1)
              ;; pdf-tools is prone to flicker and page resets when global
              ;; auto-revert polls these buffers.
              (auto-revert-mode -1)
              ;; `pdf-view-roll-minor-mode' currently breaks navigation in this
              ;; setup; keep the standard page-aware pdf-view bindings.
              (when (bound-and-true-p pdf-view-roll-minor-mode)
                (pdf-view-roll-minor-mode -1))
              (when (bound-and-true-p evil-local-mode)
                (evil-normal-state))))
  (with-eval-after-load 'evil
    (evil-set-initial-state 'pdf-view-mode 'normal)
    (define-key pdf-view-mode-map (kbd "M-;")
      (lookup-key (evil-get-auxiliary-keymap general-override-mode-map 'normal t)
                  (kbd "M-;")))
    (evil-define-key 'normal pdf-view-mode-map
      (kbd "j") #'pdf-view-next-line-or-next-page
      (kbd "k") #'pdf-view-previous-line-or-previous-page
      (kbd "C-f") #'pdf-view-scroll-up-or-next-page
      (kbd "C-b") #'pdf-view-scroll-down-or-previous-page)))

;; ------------------------------
;; Terminal inside Emacs
;; ------------------------------
(use-package vterm
  :commands vterm
  :config
  (add-hook 'vterm-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  ;; Override vterm's meta-key catch-all so M-; (leader) reaches general.
  ;; Must append (t) so it runs after vterm-mode finishes binding keys.
  (add-hook 'vterm-mode-hook
    (lambda ()
      (define-key vterm-mode-map (kbd "M-;")
        (lookup-key (evil-get-auxiliary-keymap general-override-mode-map 'normal t)
                    (kbd "M-;"))))
    t)
  (with-eval-after-load 'evil
    ;; Keep terminal buffers in emacs state so TUI keybindings pass through.
    (evil-set-initial-state 'vterm-mode 'emacs)
    (add-hook 'vterm-mode-hook #'evil-emacs-state))
 )

(use-package ghostel
  :straight (ghostel :host github :repo "dakra/ghostel")
  :commands ghostel
  :config
  (add-hook 'ghostel-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  (with-eval-after-load 'evil
    (evil-set-initial-state 'ghostel-mode 'emacs)
    (add-hook 'ghostel-mode-hook #'evil-emacs-state))
  (general-define-key
   :keymaps 'ghostel-mode-map
   "M-;" (lookup-key (evil-get-auxiliary-keymap general-override-mode-map 'normal t) (kbd "M-;"))))

(use-package eat
  :commands eat
  :straight (eat :host codeberg :repo "akib/emacs-eat")
  :config
  (add-hook 'eat-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  (with-eval-after-load 'evil
    (evil-set-initial-state 'eat-mode 'emacs)
    (add-hook 'eat-mode-hook #'evil-emacs-state))
  (general-define-key
   :keymaps 'eat-mode-map
   "M-;" (lookup-key (evil-get-auxiliary-keymap general-override-mode-map 'normal t) (kbd "M-;"))))

(use-package agent-shell-notifications
  :straight (agent-shell-notifications
              :type git
              :host github
              :repo "zackattackz/agent-shell-notifications")
  :hook
  (agent-shell-mode . agent-shell-notifications-mode)
  :config
  (setq agent-shell-notifications-idle-timeout 10)
  (setq agent-shell-notifications-timeout 0)
  (setq agent-shell-notifications-provider 'agent-shell-notifications-knockknock))

(use-package knockknock
  :straight (knockknock :type git :host github :repo "konrad1977/knockknock")
  :config
  (setq knockknock-use-svg-layout t)
  (setq knockknock-default-duration 0)
  (setq knockknock-poshandler #'posframe-poshandler-frame-top-center)
  (setq knockknock-background-color "#1e1e2e")
  (setq knockknock-foreground-color "#cdd6f4")
  (setq knockknock-border-color "#89b4fa")
  (setq knockknock-border-width 2))

(defun my/agent-shell-notifications-format (type event)
  "Custom notification format with different icons per event type."
  (pcase type
    ('turn-complete (list :title "Agent Ready" :icon "cod-check" :body (format "Response ready: %s" (cdr (assoc-default 'text event)))))
    ('permission-request (list :title "Permission Needed" :icon "cod-question" :body (format "%s" (cdr (assoc-default 'text event)))))
    ('error (list :title "Agent Error" :icon "cod-error" :body (format "Error: %s" (cdr (assoc-default 'message event)))))
    (_ (list :title "Agent" :icon "cod-comment-discussion" :body (format "%s" (cdr (assoc-default 'text event)))))))

(setq agent-shell-notifications-format-function #'my/agent-shell-notifications-format)

(use-package agent-shell-manager
  :straight (agent-shell-manager
              :type git
              :host github
              :repo "jethrokuan/agent-shell-manager")
  :config
  (setq agent-shell-manager-side 'bottom))

(use-package agent-review
  :straight (agent-review
              :type git
              :host github
              :repo "nineluj/agent-review")
  :commands agent-review)

(use-package meta-agent-shell
  :straight (meta-agent-shell
              :type git
              :host github
              :repo "ElleNajt/meta-agent-shell")
  :after agent-shell
  :config
  (setq meta-agent-shell-heartbeat-file "~/heartbeat.org")
  (setq meta-agent-shell-start-function #'agent-shell))

(use-package agent-shell-knockknock
  :straight (agent-shell-knockknock
              :type git
              :host github
              :repo "xenodium/agent-shell-knockknock")
  :after (agent-shell knockknock)
  :hook (agent-shell-mode . agent-shell-knockknock-mode))

(defun my/agent-shell-force-reset ()
  "Force-reset agent-shell busy state when stuck after a failed interrupt."
  (interactive)
  (unless (derived-mode-p 'agent-shell-mode)
    (user-error "Not in an agent-shell buffer"))
  (when (bound-and-true-p shell-maker--busy)
    (shell-maker-interrupt))
  (when (map-nested-elt (agent-shell--state) '(:heartbeat :heartbeat-timer))
    (agent-shell-heartbeat-stop
     :heartbeat (map-elt (agent-shell--state) :heartbeat)))
  (message "Agent shell reset."))

(defun my/agent-shell-session-status ()
  "Show current session info: mode, model, context usage, and busy state."
  (interactive)
  (unless (derived-mode-p 'agent-shell-mode)
    (user-error "Not in an agent-shell buffer"))
  (let* ((state (agent-shell--state))
         (session-id (map-nested-elt state '(:session :id)))
         (mode-id (map-nested-elt state '(:session :mode-id)))
         (model-id (map-nested-elt state '(:set-model)))
         (busy (bound-and-true-p shell-maker--busy))
         (heartbeat-status (map-nested-elt state '(:heartbeat :status))))
    (message "Session: %s | Mode: %s | Busy: %s | Heartbeat: %s%s"
             (or session-id "none")
             (or mode-id "default")
             busy
             (or heartbeat-status "none")
              (if (agent-shell--usage-has-data-p (map-elt state :usage))
                  (format " | %s" (agent-shell--format-usage (map-elt state :usage)))
                ""))))

(defvar my/agent-shell-debug-diffs t
  "When non-nil, log diff extraction details for agent-shell tool calls.")

(defun my/agent-shell--debug-log (format-string &rest args)
  "Append a formatted debug line to the agent-shell diff log buffer."
  (when my/agent-shell-debug-diffs
    (with-current-buffer (get-buffer-create "*agent-shell-diff-debug*")
      (goto-char (point-max))
      (insert (format-time-string "[%F %T] "))
      (insert (apply #'format format-string args))
      (insert "\n"))))

(defun my/agent-shell-open-diff-debug-log ()
  "Open the agent-shell diff debug log buffer."
  (interactive)
  (pop-to-buffer (get-buffer-create "*agent-shell-diff-debug*")))

(defun my/agent-shell-clear-diff-debug-log ()
  "Clear the agent-shell diff debug log buffer."
  (interactive)
  (with-current-buffer (get-buffer-create "*agent-shell-diff-debug*")
    (erase-buffer))
  (message "Cleared *agent-shell-diff-debug*"))

(defun my/agent-shell--map-keys (value)
  "Return VALUE's keys as strings when it looks like a map/alist."
  (cond
   ((vectorp value)
    nil)
   ((listp value)
    (delq nil
          (mapcar (lambda (entry)
                    (when (consp entry)
                      (format "%s" (car entry))))
                  value)))
   (t nil)))

(defun my/agent-shell--content-summary (content)
  "Return a compact summary of CONTENT payload types."
  (cond
   ((null content)
    nil)
   ((vectorp content)
    (mapcar (lambda (item) (map-elt item 'type)) content))
   ((and (listp content)
         (consp content)
         (assoc 'type content))
    (list (map-elt content 'type)))
   ((listp content)
    (mapcar (lambda (item)
              (when (listp item)
                (map-elt item 'type)))
            content))
   (t
    (list (format "%s" (type-of content))))))

(defun my/agent-shell--debug-make-diff-info (fn &rest args)
  "Log `agent-shell--make-diff-info' inputs and outputs around FN."
  (let* ((acp-tool-call (plist-get args :acp-tool-call))
         (raw-input (map-elt acp-tool-call 'rawInput))
         (content (map-elt acp-tool-call 'content))
         (result (apply fn args)))
    (my/agent-shell--debug-log
     "make-diff-info title=%S kind=%S status=%S content-types=%S raw-input-keys=%S flags=%S result-keys=%S"
     (map-elt acp-tool-call 'title)
     (map-elt acp-tool-call 'kind)
     (map-elt acp-tool-call 'status)
     (my/agent-shell--content-summary content)
     (my/agent-shell--map-keys raw-input)
     `((patchText . ,(and raw-input (map-elt raw-input 'patchText) t))
       (diff . ,(and raw-input (map-elt raw-input 'diff) t))
       (new_str . ,(and raw-input (map-elt raw-input 'new_str) t))
       (newString . ,(and raw-input (map-elt raw-input 'newString) t))
       (newText . ,(and raw-input (map-elt raw-input 'newText) t)))
     (my/agent-shell--map-keys result))
    (when (and raw-input
               (or (map-elt raw-input 'patchText)
                   (map-elt raw-input 'diff)
                   (map-elt raw-input 'new_str)
                   (map-elt raw-input 'newString)
                   (map-elt raw-input 'newText))
               (null result))
      (my/agent-shell--debug-log
       "raw-input=%S content=%S"
       raw-input
       content))
    result))

(defun my/agent-shell--make-diff-info-compat (fn &rest args)
  "Extend `agent-shell--make-diff-info' for OpenCode diff payloads.

This fills the current gaps in upstream `agent-shell':
- `rawInput.filepath' instead of `path' or `fileName'
- `rawInput.patchText' from `apply_patch'

It defers to upstream first and only synthesizes a diff when upstream
returns nil."
  (or (apply fn args)
      (let* ((acp-tool-call (plist-get args :acp-tool-call))
             (raw-input (map-elt acp-tool-call 'rawInput))
             (patch-text (and raw-input (map-elt raw-input 'patchText)))
             (diff-text (and raw-input (map-elt raw-input 'diff)))
             (file-path (and raw-input
                             (or (map-elt raw-input 'filepath)
                                 (map-elt raw-input 'filePath)
                                 (map-elt raw-input 'path)
                                 (map-elt raw-input 'fileName))))
             (parsed (cond
                      (patch-text
                       (agent-shell--parse-unified-diff patch-text))
                      (diff-text
                       (agent-shell--parse-unified-diff diff-text)))))
        (when (and parsed file-path)
          (list (cons :old (car parsed))
                (cons :new (cdr parsed))
                (cons :file file-path))))))

(defun my/agent-shell--inline-permission-diff (fn &rest args)
  "Append inline diff text to tool permission prompts when available."
  (let* ((body (apply fn args))
         (acp-request (plist-get args :acp-request))
         (state (plist-get args :state))
         (tool-call-id (map-nested-elt acp-request '(params toolCall toolCallId)))
         (diff (and state tool-call-id
                    (map-nested-elt state `(:tool-calls ,tool-call-id :diff))))
         (diff-text (and diff (agent-shell--format-diff-as-text diff))))
    (if diff-text
        (concat
                "    \n"
                "    ╭─────────╮\n"
                "    │ changes │\n"
                "    ╰─────────╯\n\n"
                (replace-regexp-in-string "^" "    " diff-text)
                "\n\n"
                body)
      body)))

(defun my/agent-shell--hide-view-diff-button (fn &rest args)
  "Hide the visible `View (v)' button from permission prompts.

Upstream still wires the `v' action into the permission keymap, but this keeps
the button itself out of the rendered prompt so inline diffs are the only
visible affordance."
  (let ((body (apply fn args)))
    (replace-regexp-in-string
     "[[:space:]]*\\[ View (v) \\][[:space:]]*"
     " "
     body)))

(defun my/agent-shell--suppress-view-diff-button (fn &rest args)
  "Return no visible button for the upstream `view diff' permission action."
  (if (equal (plist-get args :option) "view diff")
      ""
    (apply fn args)))

(defvar my/agent-shell-permission-feedback-kinds '("edit" "write")
  "Tool call kinds that should offer optional feedback after permission choices.")

(defvar my/agent-shell-permission-actions (make-hash-table :test 'equal)
  "Permission actions keyed by shell buffer, request id, and tool call id.")

(defun my/agent-shell--permission-action-key (&key state request-id tool-call-id)
  "Build the lookup key for a permission action set."
  (list (map-elt state :buffer) request-id tool-call-id))

(defun my/agent-shell--remember-permission-actions (fn &rest args)
  "Remember permission actions before FN renders the default permission UI."
  (when-let* ((acp-request (plist-get args :acp-request))
              (state (plist-get args :state))
              (request-id (map-elt acp-request 'id))
              (tool-call-id (map-nested-elt acp-request '(params toolCall toolCallId))))
    (puthash (my/agent-shell--permission-action-key
              :state state :request-id request-id :tool-call-id tool-call-id)
             (agent-shell--make-permission-actions
              (map-nested-elt acp-request '(params options)))
             my/agent-shell-permission-actions))
  (apply fn args))

(defun my/agent-shell--queue-permission-feedback (buffer prompt)
  "Prompt for optional feedback and submit it to BUFFER."
  (let ((feedback (read-string prompt)))
    (when (and (buffer-live-p buffer)
               (not (string-empty-p feedback)))
      (run-at-time 0.2 nil
                   (lambda (shell-buffer msg)
                     (when (buffer-live-p shell-buffer)
                       (with-current-buffer shell-buffer
                         (agent-shell-insert :text msg :submit t))))
                   buffer feedback))))

(defun my/agent-shell--permission-feedback-response (fn &rest args)
  "After FN resolves a permission, optionally collect feedback for edit/write actions."
  (let* ((state (plist-get args :state))
         (request-id (plist-get args :request-id))
         (tool-call-id (plist-get args :tool-call-id))
         (option-id (plist-get args :option-id))
         (cancelled (plist-get args :cancelled))
         (key (and state request-id tool-call-id
                   (my/agent-shell--permission-action-key
                    :state state :request-id request-id :tool-call-id tool-call-id)))
         (actions (and key (gethash key my/agent-shell-permission-actions)))
         (action (and option-id
                      (seq-find (lambda (candidate)
                                  (equal (map-elt candidate :option-id) option-id))
                                actions)))
         (action-kind (map-elt action :kind))
         (tool-kind (and state tool-call-id
                         (map-nested-elt state `(:tool-calls ,tool-call-id :kind))))
         (tool-title (and state tool-call-id
                          (map-nested-elt state `(:tool-calls ,tool-call-id :title))))
         (buffer (and state (map-elt state :buffer))))
    (unwind-protect
        (prog1 (apply fn args)
          (when (and (not cancelled)
                     (member tool-kind my/agent-shell-permission-feedback-kinds)
                     (member action-kind '("allow_once" "reject_once"))
                     (buffer-live-p buffer))
            (my/agent-shell--queue-permission-feedback
             buffer
             (format "%s feedback for %s (optional): "
                     (if (string= action-kind "allow_once") "Accept" "Reject")
                     (or tool-title tool-kind)))))
      (when key
        (remhash key my/agent-shell-permission-actions)))))

(use-package agent-shell
  :commands (agent-shell
             agent-shell-opencode-start-agent
             agent-shell-anthropic-start-claude-code
             agent-shell-toggle
             agent-shell-send-region
             agent-shell-send-file)
  :init
  (setq agent-shell-anthropic-default-session-mode-id "code"
        agent-shell-show-usage-at-turn-end t
        agent-shell-show-context-usage-indicator 'detailed
        agent-shell-prefer-viewport-interaction nil
        agent-shell-thought-process-expand-by-default t
        agent-shell-tool-use-expand-by-default t)
  :config
  (setq agent-shell-permission-responder-function nil)
  (advice-remove 'agent-shell--make-diff-info #'my/agent-shell--make-diff-info-compat)
  (advice-add 'agent-shell--make-diff-info :around #'my/agent-shell--make-diff-info-compat)
  (advice-remove 'agent-shell--make-diff-info #'my/agent-shell--debug-make-diff-info)
  (advice-add 'agent-shell--make-diff-info :around #'my/agent-shell--debug-make-diff-info)
  (advice-remove 'agent-shell--make-tool-call-permission-text #'my/agent-shell--hide-view-diff-button)
  (advice-add 'agent-shell--make-tool-call-permission-text :around #'my/agent-shell--hide-view-diff-button)
  (advice-remove 'agent-shell--make-permission-button #'my/agent-shell--suppress-view-diff-button)
  (advice-add 'agent-shell--make-permission-button :around #'my/agent-shell--suppress-view-diff-button)
  (advice-remove 'agent-shell--make-tool-call-permission-text #'my/agent-shell--inline-permission-diff)
  (advice-add 'agent-shell--make-tool-call-permission-text :around #'my/agent-shell--inline-permission-diff)
  ;; Feedback advice disabled for now - it hangs when read-string runs during busy state
  ;; (advice-remove 'agent-shell--make-tool-call-permission-text #'my/agent-shell--remember-permission-actions)
  ;; (advice-add 'agent-shell--make-tool-call-permission-text :around #'my/agent-shell--remember-permission-actions)
  ;; (advice-remove 'agent-shell--send-permission-response #'my/agent-shell--permission-feedback-response)
  ;; (advice-add 'agent-shell--send-permission-response :around #'my/agent-shell--permission-feedback-response)
  (add-hook 'agent-shell-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  (with-eval-after-load 'evil
    (evil-define-key 'insert agent-shell-mode-map (kbd "RET") #'newline)
    (evil-define-key 'normal agent-shell-mode-map (kbd "RET") #'comint-send-input)
    (add-hook 'diff-mode-hook
              (lambda ()
                (when (string-match-p "\\*agent-shell-diff\\*" (buffer-name))
                  (evil-emacs-state))))
    (dolist (state '(normal motion))
      (evil-define-key state agent-shell-mode-map
        (kbd "C-c C-k") #'my/agent-shell-force-reset)))
  (define-key agent-shell-mode-map (kbd "C-c C-k") #'my/agent-shell-force-reset))

(with-eval-after-load 'general
  (my/leader
    "a"   '(:ignore t :which-key "ai")
    "a a" '(agent-shell :which-key "agent shell")
    "a o" '(agent-shell-opencode-start-agent :which-key "opencode")
    "a c" '(agent-shell-anthropic-start-claude-code :which-key "claude")
    "a t" '(agent-shell-toggle :which-key "toggle")
    "a s" '(agent-shell-send-region :which-key "send region")
    "a m" '(agent-shell-set-session-mode :which-key "set mode")
    "a M" '(agent-shell-set-session-model :which-key "set model")
    "a u" '(agent-shell-show-usage :which-key "usage")
    "a S" '(my/agent-shell-session-status :which-key "session status")
    "a L" '(my/agent-shell-open-diff-debug-log :which-key "diff debug log")
    "a l" '(agent-shell-view-acp-logs :which-key "ACP logs")
    "a r" '(my/agent-shell-force-reset :which-key "force reset")
    "a C" '(my/agent-shell-clear-diff-debug-log :which-key "clear diff debug log")
    "a R" '(agent-review :which-key "review code")
    "a d" '(agent-shell-manager-toggle :which-key "manager")
    "a n" '(knockknock-close :which-key "close notification")))

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

;; Tree-sitter grammar sources
(setq treesit-language-source-alist
      '((typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
        (tsx        "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
        (javascript "https://github.com/tree-sitter/tree-sitter-javascript" "master" "src")))

;; (treesit-query-compile predicate-strip advice lives near top of init.el so
;; it's installed before persp-mode restores any .ts/.tsx buffers.)

(use-package eglot
  :commands (eglot eglot-ensure)
  :init
  ;; Auto-install missing tree-sitter grammars
  (defun my/treesit-install-missing-grammars ()
    "Install missing tree-sitter grammars for typescript, tsx, and javascript."
    (dolist (lang '(typescript tsx javascript))
      (unless (treesit-language-available-p lang)
        (treesit-install-language-grammar lang))))

  (add-hook 'emacs-startup-hook #'my/treesit-install-missing-grammars)

  ;; Auto-start LSP for TypeScript/JavaScript modes
  (dolist (mode '(typescript-ts-mode tsx-ts-mode js-ts-mode))
    (add-hook (intern (format "%s-hook" mode)) #'eglot-ensure))
  ;; Associate TS files with proper major modes
  (add-to-list 'auto-mode-alist '("\\.ts\\'"  . typescript-ts-mode))
  (add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))
  (add-to-list 'auto-mode-alist '("\\.js\\'"  . js-ts-mode))
  (add-to-list 'auto-mode-alist '("\\.jsx\\'" . js-ts-mode))

  :config
  (setq eglot-autoshutdown t
        eglot-send-changes-idle-time 0.2)
  ;; Use vtsls for TypeScript (install: npm install -g @vtsls/language-server)
  (add-to-list 'eglot-server-programs
               '((typescript-ts-mode tsx-ts-mode) . ("vtsls" "--stdio")))
  ;; Route xref through consult for telescope-style references popup
  (with-eval-after-load 'consult
    (require 'consult-xref)
    (setq xref-show-xrefs-function      #'consult-xref
          xref-show-definitions-function #'consult-xref))
  ;; consult-flymake for error list
  (with-eval-after-load 'consult
    (require 'consult-flymake)))

;; ------------------------------
;; Org: second brain + literate programming
;; ------------------------------
(use-package org
  :straight (:type built-in)
  :init
  (setq org-directory (expand-file-name my/lifeos-dir)
        org-hide-emphasis-markers t
        org-startup-indented t
        org-ellipsis " ▾"
        org-log-done 'time
        org-src-tab-acts-natively t
        org-confirm-babel-evaluate nil
        org-id-link-to-org-use-id t
        org-id-locations-file (expand-file-name ".org-id-locations" user-emacs-directory))
  :config
  (add-to-list 'org-modules 'org-habit t)
  (org-load-modules-maybe t)

  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (python . t)
     (shell . t)))

  (add-hook 'org-capture-prepare-final-hook 'org-id-get-create)

  (let* ((inbox (expand-file-name "inbox.org" org-directory))
         (tasks (expand-file-name "tasks.org" org-directory))
         (projects (expand-file-name "projects.org" org-directory))
         (goals (expand-file-name "goals.org" org-directory))
         (milestones (expand-file-name "milestones.org" org-directory))
         (habits (expand-file-name "habits.org" org-directory))
         (routines (expand-file-name "routines.org" org-directory))
         (journal (expand-file-name "journal.org" org-directory))
         (goal-year (format-time-string "%Y")))
    (setq org-default-notes-file inbox
          org-agenda-files (list inbox tasks projects goals milestones habits routines)
          org-refile-targets `((,tasks :maxlevel . 2)
                               (,projects :maxlevel . 2)
                               (,goals :maxlevel . 3)
                               (,milestones :maxlevel . 2)
                               (,habits :maxlevel . 2)
                               (,routines :maxlevel . 2))
          org-outline-path-complete-in-steps nil
          org-refile-use-outline-path 'file
          org-enforce-todo-dependencies t
          org-cycle-hide-drawer-startup t
          org-hide-leading-stars t
          org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "SOMEDAY(s)" "|" "DONE(d)" "CANCELLED(c)"))
          org-capture-templates
          `(("t" "Task" entry
             (file+headline ,inbox "Tasks To Process")
             "* TODO %? #task\n:PROPERTIES:\n:CREATED: %U\n:PROJECT_REF: \n:GOAL_REF: \n:CONTEXT: \n:DAILY_PRIORITY: \n:TIME_EST_HOURS: \n:END:\n"
             :prepend t)
            ("n" "Note" entry
             (file+headline ,inbox "Notes To Process")
             "* %? #note\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
             :prepend t)
            ("p" "Project" entry
             (file+headline ,projects "Projects")
             "** TODO %? #project\n:PROPERTIES:\n:CREATED: %U\n:GOAL_REF: \n:PRIORITY_LEVEL: %^{Priority|low|medium|high|urgent}\n:REVIEW_FREQUENCY: 7\n:LAST_REVIEW:\n:NEXT_REVIEW:\n:END:\n"
             :prepend t)
            ("g" "Goal" entry
             (file+headline ,goals ,goal-year)
             "** TODO %? #goal\n:PROPERTIES:\n:CREATED: %U\n:YEAR: %<%Y>\n:QUARTER: %^{Quarter|Q1|Q2|Q3|Q4}\n:MONTH: %^{Month|January|February|March|April|May|June|July|August|September|October|November|December}\n:REVIEW_FREQUENCY: 30\n:END:\n"
             :prepend t)
            ("m" "Milestone" entry
             (file+headline ,milestones goal-year)
             "** TODO %? #milestone\n:PROPERTIES:\n:CREATED: %U\n:GOAL_REF: \n:YEAR: %<%Y>\n:END:\nDEADLINE: %^t\n"
             :prepend t)
            ("h" "Habit" entry
             (file+headline ,habits "Habits")
             "** TODO %? #habit\n:PROPERTIES:\n:CREATED: %U\n:GOAL_REF: \n:TRACKING_MODE: %^{Tracking mode|checklist|quantitative}\n:CADENCE: %^{Cadence|daily|weekly|custom}\n:TARGET_PER_WEEK: %^{Target per week|1|3|5|7}\n:START_DATE: %<%Y-%m-%d>\n:END:\n"
             :prepend t)
            ("r" "Routine" entry
             (file+headline ,routines "Routine Inbox")
             "** TODO %? #routine\n:PROPERTIES:\n:CREATED: %U\n:ROUTINE_TYPE: %^{Routine type|morning|evening}\n:CATEGORY: %^{Category|planning|physical|mental|hygiene|medication|wind-down|other}\n:REQUIRED: %^{Required|yes|no}\n:SEQUENCE_ORDER:\n:TIME_ESTIMATE:\n:PROMPT_TOKEN:\n:ALARM_CREATED: no\n:ALARM_SCHEDULED_FOR:\n:SNOOZE_UNTIL:\n:END:\n"
             :prepend t)
            ("j" "Journal (today)" entry
             (file+olp+datetree ,journal)
             "* Daily note\n:PROPERTIES:\n:ENERGY:\n:MOOD:\n:END:\n\n- Summary :: %?\n- Notes :: \n"))
          org-agenda-custom-commands
          (list
           `("d" "LifeOS dashboard"
             ((agenda ""
                      ((org-agenda-span 1)
                       (org-deadline-warning-days 7)
                       (org-agenda-overriding-header "Today")))
              (alltodo ""
                       ((org-agenda-overriding-header "Inbox And Tasks")
                        (org-agenda-files (list ,inbox ,tasks))
                        (org-super-agenda-groups
                         '((:name "Inbox" :file-path "inbox.org")
                           (:name "Overdue" :deadline past)
                           (:name "Due Today" :deadline today)
                           (:name "Scheduled Today" :scheduled today)
                           (:name "Next Actions" :todo "NEXT")
                           (:name "Waiting" :todo "WAITING")
                           (:name "Someday" :todo "SOMEDAY")
                           (:discard (:todo "DONE"))
                           (:discard (:todo "CANCELLED"))))))
              (alltodo ""
                       ((org-agenda-overriding-header "Projects")
                        (org-agenda-files (list ,projects))
                        (org-super-agenda-groups
                         '((:name "Active Projects" :todo "NEXT")
                           (:name "Waiting Projects" :todo "WAITING")
                           (:name "Project Backlog" :todo "TODO")
                           (:name "Someday Projects" :todo "SOMEDAY")
                           (:discard (:todo "DONE"))
                           (:discard (:todo "CANCELLED"))))))))
           `("n" "Next actions" todo "NEXT"
             ((org-agenda-files (list ,tasks))))
           `("w" "Waiting" todo "WAITING"
             ((org-agenda-files (list ,tasks ,projects))))
           `("r" "Project reviews" alltodo ""
             ((org-agenda-overriding-header "Project Reviews")
              (org-agenda-files (list ,projects))
              (org-super-agenda-groups
               '((:name "Active Projects" :todo "NEXT")
                 (:name "Waiting Projects" :todo "WAITING")
                 (:name "Backlog Projects" :todo "TODO")
                 (:discard (:todo "DONE"))
                 (:discard (:todo "CANCELLED"))))))
           `("h" "Habits" alltodo ""
             ((org-agenda-files (list ,habits))
              (org-agenda-overriding-header "Habits")
              (org-super-agenda-groups
               '((:name "Habits" :todo ("TODO" "NEXT" "WAITING" "SOMEDAY"))
                 (:discard (:todo "DONE"))
                 (:discard (:todo "CANCELLED"))))))))))

(defun my/org-today-file ()
  "Return path to today's daily note file."
  (expand-file-name (format-time-string "daily/%Y-%m-%d.org") org-directory))

(defun my/org-open-today ()
  "Open today's daily note."
  (interactive)
  (find-file (my/org-today-file)))

(defun my/lifeos-file (name)
  "Return absolute path for NAME inside `org-directory'."
  (expand-file-name name org-directory))

(defun my/lifeos-open-file (name)
  "Open lifeos file NAME from `org-directory'."
  (interactive)
  (find-file (my/lifeos-file name)))

(defun my/lifeos-open-inbox ()
  "Open inbox.org."
  (interactive)
  (my/lifeos-open-file "inbox.org"))

(defun my/lifeos-open-tasks ()
  "Open tasks.org."
  (interactive)
  (my/lifeos-open-file "tasks.org"))

(defun my/lifeos-open-projects ()
  "Open projects.org."
  (interactive)
  (my/lifeos-open-file "projects.org"))

(defun my/lifeos-open-goals ()
  "Open goals.org."
  (interactive)
  (my/lifeos-open-file "goals.org"))

(defun my/lifeos-open-milestones ()
  "Open milestones.org."
  (interactive)
  (my/lifeos-open-file "milestones.org"))

(defun my/lifeos-open-habits-file ()
  "Open habits.org."
  (interactive)
  (my/lifeos-open-file "habits.org"))

(defun my/lifeos-open-routines ()
  "Open routines.org."
  (interactive)
  (my/lifeos-open-file "routines.org"))

(defun my/lifeos-open-journal ()
  "Open journal.org."
  (interactive)
  (my/lifeos-open-file "journal.org"))

(defun my/lifeos-open-dashboard ()
  "Open the main LifeOS dashboard agenda."
  (interactive)
  (org-agenda nil "d"))

(defun my/lifeos-open-habits ()
  "Open the habits agenda view."
  (interactive)
  (org-agenda nil "h"))

(defun my/lifeos-open-reviews ()
  "Open the project review agenda view."
  (interactive)
  (org-agenda nil "r"))

;; Move completed items to "* Completed" heading in same file
(defun my/org-archive-completed-to-completed-section ()
  "Archive completed/cancelled TODO items to a '* Completed' heading in the same file."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((completed-heading nil))
      ;; Find or create "* Completed" heading
      (while (and (not completed-heading)
                  (re-search-forward "^\\*+ " nil t))
        (when (string-equal (org-get-heading t t t t) "Completed")
          (setq completed-heading (point))))
      (unless completed-heading
        (goto-char (point-max))
        (insert "\n* Completed\n")
        (setq completed-heading (point)))
      ;; Now move completed items
      (goto-char (point-min))
      (while (re-search-forward org-heading-regexp nil t)
        (let* ((todo-state (org-get-todo-state))
               (is-done (member todo-state '("DONE" "CANCELLED"))))
          (when is-done
            (let ((heading-start (point-at-bol))
                  (heading-end (save-excursion
                                 (outline-next-heading)
                                 (point))))
              (kill-region heading-start heading-end)
              (goto-char completed-heading)
              (yank)
              (setq completed-heading (point))
              (goto-char heading-start))))))))

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
  (org-roam-db-autosync-mode 1))

(use-package org-supertag
  :straight (:host github :repo "yibie/org-supertag")
  :after org
  :init
  (setq org-supertag-sync-directories (list org-directory)
        supertag-data-directory
        (expand-file-name "org-supertag/" my/config-root-dir))
  :config
  (defun my/lifeos-supertag-initialize ()
    "Initialize org-supertag for the LifeOS directory."
    (interactive)
    (supertag-sync-full-initialize))

  (defun my/lifeos-supertag-rescan ()
    "Rescan LifeOS files into the org-supertag database."
    (interactive)
    (supertag-sync-full-rescan)))

;; ------------------------------
;; Org extras: search, navigation, notifications, pomodoro
;; ------------------------------
(use-package org-ql
  :after org)

(use-package org-super-agenda
  :after org
  :config
  (org-super-agenda-mode 1))

(use-package org-wild-notifier
  :after org
  :config
  (setq org-wild-notifier-alert-time '(10 30 60)
        org-wild-notifier-notification-title "lifeos"
        org-wild-notifier-keyword-whitelist nil)
  (org-wild-notifier-mode 1))

(use-package org-tidy
  :after org
  :hook (org-mode . org-tidy-mode)
  :config
  (setq org-tidy-properties-inline-symbol "♯"))

(use-package org-sticky-header
  :after org
  :hook (org-mode . org-sticky-header-mode)
  :config
  (setq org-sticky-header-full-path 'full
        org-sticky-header-outline-path-separator " > "))

(use-package org-agenda-property
  :after org
  :config
  (setq org-agenda-property-list '("ENERGY" "CONTEXT" "RELATED_PROJECT" "REVIEW_FREQUENCY"))
  (setq org-agenda-property-position 'right))

(use-package org-pomodoro
  :after org
  :config
  (setq org-pomodoro-length 25
        org-pomodoro-short-break-length 5
        org-pomodoro-long-break-length 15
        org-pomodoro-long-break-frequency 4))

(use-package org-sidebar
  :after org)

(with-eval-after-load 'org-agenda
  (general-define-key
   :keymaps 'org-agenda-mode-map
   "M-;" (lookup-key (evil-get-auxiliary-keymap general-override-mode-map 'normal t)
                     (kbd "M-;"))))

(use-package calfw
  :after org)
(use-package calfw-org
  :after (org calfw)
  :config
  (defun my/calfw-open ()
    "Open calfw calendar showing org agenda items."
    (interactive)
    (cfw:open-calendar-buffer
     :contents-sources
     (list (cfw:org-create-source "Green"))))

  )

(with-eval-after-load 'general
  (my/leader
    "n v" '(my/calfw-open :which-key "calendar")
    "n I" '(my/lifeos-open-inbox :which-key "inbox")
    "n T" '(my/lifeos-open-tasks :which-key "tasks")
    "n P" '(my/lifeos-open-projects :which-key "projects")
    "n G" '(my/lifeos-open-goals :which-key "goals")
    "n M" '(my/lifeos-open-milestones :which-key "milestones")
    "n H" '(my/lifeos-open-habits-file :which-key "habits")
    "n R" '(my/lifeos-open-routines :which-key "routines")
    "n J" '(my/lifeos-open-journal :which-key "journal")
    "n u" '(my/lifeos-supertag-initialize :which-key "supertag init")
    "n U" '(my/lifeos-supertag-rescan :which-key "supertag rescan")))

(use-package org-time-budgets
  :after org
  :config
  (setq org-time-budgets
        `((:title "Work"    :match "work"     :budget "6:00"  :blocks (workday week))
          (:title "School"  :match "school"   :budget "4:00"  :blocks (workday week))
          (:title "Personal" :match "personal" :budget "3:00"  :blocks (day week)))))

;; OpenSpec — spec-driven project context for org capture
(use-package openspec
  :straight (:host github :repo "Zacalot/openspec.el")
  :after org
  :config
  (defun my/openspec-project-file ()
    "Return the openspec project file path for the current project, or nil."
    (when-let* ((proj (project-current))
                (root (project-root proj))
                (spec-file (expand-file-name "openspec/project.md" root)))
      (when (file-exists-p spec-file)
        spec-file)))

  (defun my/openspec-capture-project ()
    "Capture a TODO into the current project's openspec-project.org file, or fall back to tasks.org."
    (interactive)
    (if-let* ((proj (project-current))
              (root (project-root proj))
              (spec-dir (expand-file-name "openspec/" root)))
        (progn
          (unless (file-exists-p spec-dir)
            (make-directory spec-dir t))
          (let ((org-file (expand-file-name "project-todos.org" spec-dir)))
            (find-file org-file)
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (org-capture nil "t")))
      (org-capture nil "t")))

  (defun my/openspec-goto-project-todos ()
    "Open project-todos.org for the current project, or prompt for one."
    (interactive)
    (if-let* ((proj (project-current))
              (root (project-root proj))
              (spec-dir (expand-file-name "openspec/" root))
              (todo-file (expand-file-name "project-todos.org" spec-dir)))
        (find-file todo-file)
      (find-file (expand-file-name "tasks.org" org-directory))))

  (with-eval-after-load 'general
    (my/leader
      "n p t" '(my/openspec-capture-project :which-key "capture project task")
      "n p f" '(my/openspec-goto-project-todos :which-key "find project todos"))))

;; ------------------------------
;; Markdown
;; ------------------------------
(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :init
  (setq markdown-fontify-code-blocks-natively t
        markdown-hide-markup nil)
  :config
  ;; Scale headers without touching colors — let the active theme decide
  (dolist (spec '((markdown-header-face-1 . 1.4)
                  (markdown-header-face-2 . 1.3)
                  (markdown-header-face-3 . 1.2)
                  (markdown-header-face-4 . 1.1)))
    (set-face-attribute (car spec) nil
                        :height (cdr spec)
                        :weight 'bold)))

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

(defun my/toggle-fullscreen ()
  "Toggle between full-screen and maximized window."
  (interactive)
  (if (frame-parameter nil 'fullscreen)
      (set-frame-parameter nil 'fullscreen 'maximized)
    (set-frame-parameter nil 'fullscreen 'fullboth)))

(with-eval-after-load 'general
  (my/leader
    "t f"  '(set-frame-font :which-key "set font (prompt)")
    "t +"  '(my/font-bigger :which-key "font bigger")
    "t -"  '(my/font-smaller :which-key "font smaller")
    "t F"  '(my/toggle-fullscreen :which-key "toggle fullscreen")
    "t p"  '(my/toggle-vertico-posframe :which-key "toggle posframe")))

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
        modus-themes-prompts '(bold intense)))

(use-package doom-themes
  :demand t
  :config
  (load-theme 'doom-gruvbox t))
  ;; Make line numbers more visible
  ;; (set-face-attribute 'line-number nil
  ;;                    :foreground "#5c6370"
  ;;                  :background 'unspecified
  ;;                :weight 'normal)
  ;; (set-face-attribute 'line-number-current-line nil
  ;;                     :foreground "#abb2bf"
  ;;                     :background "#3e4451"
  ;;                     :weight 'bold))

(use-package nerd-icons)
(use-package doom-modeline
  :demand t
  :init
  (setq doom-modeline-height 40
        doom-modeline-modal-icon nil)   ; plain text state indicator (N/I/V) instead of circle icon
  :config
  ;; Hide noisy segments
  (setq doom-modeline-buffer-encoding nil       ; always utf-8, not useful
        doom-modeline-enable-buffer-position nil ; hide L478
        doom-modeline-percent-position nil)      ; hide 45%
  ;; Scale up the mode-line text (1.1 = 110% of default font size)
  (custom-set-faces
   '(mode-line          ((t :height 1.1)))
   '(mode-line-inactive ((t :height 1.1))))
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
   '("7ec8fd456c0c117c99e3a3b16aaf09ed3fb91879f6601b1ea0eeaee9c6def5d9"
     "38b43b865e2be4fe80a53d945218318d0075c5e01ddf102e9bec6e90d57e2134"
     "4990532659bb6a285fee01ede3dfa1b1bdf302c5c3c8de9fad9b6bc63a9252f7"
     "d481904809c509641a1a1f1b1eb80b94c58c210145effc2631c1a7f2e4a2fdf4"
     "8c7e832be864674c220f9a9361c851917a93f921fedb7717b1b5ece47690c098"
     "3613617b9953c22fe46ef2b593a2e5bc79ef3cc88770602e7e569bbd71de113b"
     "720838034f1dd3b3da66f6bd4d053ee67c93a747b219d1c546c41c4e425daf93"
     "dd4582661a1c6b865a33b89312c97a13a3885dc95992e2e5fc57456b4c545176"
     "4594d6b9753691142f02e67b8eb0fda7d12f6cc9f1299a49b819312d6addad1d"
     default))
 '(warning-suppress-types '((initialization))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
;; fave themes so far: doom-challenger-deep, doom-manegarm, doom-ayu-dark, doom-horizon, doom-dracula, doom-lantern, doom-monokai-pro, doom-moonlight, doom-one, doom-gruvbox
