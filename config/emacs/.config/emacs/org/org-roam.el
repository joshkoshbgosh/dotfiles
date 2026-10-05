;; -*- lexical-binding: t -*-
;;; org/org-roam.el — Org-roam database

(use-package org-roam
  :after org
  :init
  (setq org-roam-directory (file-truename (expand-file-name "roam/" org-directory)))
  :config
  (org-roam-db-autosync-mode 1))

