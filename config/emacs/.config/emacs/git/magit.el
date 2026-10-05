;; -*- lexical-binding: t -*-
;;; git/magit.el — Magit interface

(use-package magit
  :commands (magit-status magit-log-current magit-log-all
             magit-blame magit-diff-dwim magit-file-dispatch
             magit-stage-file magit-unstage-file)
  :config
  (setq magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))

