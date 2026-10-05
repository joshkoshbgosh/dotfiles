;; -*- lexical-binding: t -*-
;;; startup/straight.el --- straight.el bootstrap and lockfile helpers

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

