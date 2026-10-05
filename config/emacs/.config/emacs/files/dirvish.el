;; -*- lexical-binding: t -*-
;;; files/dirvish.el — Dirvish file explorer

(use-package dirvish
  :demand t
  :init
  ;; Work around a known native-comp warning in dirvish-extras.el.
  (when (boundp 'native-comp-jit-compilation-deny-list)
    (add-to-list 'native-comp-jit-compilation-deny-list "dirvish-extras\\.el\\'")
    (add-to-list 'native-comp-jit-compilation-deny-list "transient--recursive-edit")
    (add-to-list 'native-comp-jit-compilation-deny-list "dimmer"))
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

