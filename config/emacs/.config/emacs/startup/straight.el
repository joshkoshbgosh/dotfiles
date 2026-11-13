;; -*- lexical-binding: t -*-
;;; startup/straight.el --- straight.el bootstrap and lockfile helpers

(defvar bootstrap-version)

;; Must be set before bootstrap.  straight's default is a single build/
;; directory shared by every Emacs, and its build cache is invalidated
;; wholesale when `emacs-version' changes (see `straight--load-build-cache').
;; That rebuild byte-compiles every package through a blocking batch Emacs
;; and re-queues native compilation for the whole tree, which froze the UI
;; for minutes on the 31.1 -> 32.0.50 upgrade in November 2026.  A
;; per-version build dir keeps the old tree usable and makes upgrades cheap.
(setq straight-use-version-specific-build-dir t)

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

;; Package declarations
(straight-use-package 'combobulate)

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

