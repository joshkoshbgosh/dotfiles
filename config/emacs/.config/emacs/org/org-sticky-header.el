;; -*- lexical-binding: t -*-
;;; org/org-sticky-header.el — Sticky header for org

(use-package org-sticky-header
  :after org
  :hook (org-mode . org-sticky-header-mode)
  :config
  (setq org-sticky-header-full-path 'full
        org-sticky-header-outline-path-separator " > "))

