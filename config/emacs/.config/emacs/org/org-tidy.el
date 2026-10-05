;; -*- lexical-binding: t -*-
;;; org/org-tidy.el — Org tidy (clean up files on save)

(use-package org-tidy
  :after org
  :hook (org-mode . org-tidy-mode)
  :config
  (setq org-tidy-properties-inline-symbol "♯"))

