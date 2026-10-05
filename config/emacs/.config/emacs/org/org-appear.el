;; -*- lexical-binding: t -*-
;;; org/org-appear.el — Org appear (reveal headings on navigation)

(use-package org-appear
  :after org
  :hook (org-mode . org-appear-mode))

