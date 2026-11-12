;; -*- lexical-binding: t -*-
;;; core/emacs.el --- core Emacs QoL settings

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
  (global-display-line-numbers-mode 1)
  ;; With evil gone there is no visual mode, so make typing over an active
  ;; region replace it the way it did in evil.  Without this, `C-SPC' plus
  ;; typing merely inserts next to the selection.
  (delete-selection-mode 1))

