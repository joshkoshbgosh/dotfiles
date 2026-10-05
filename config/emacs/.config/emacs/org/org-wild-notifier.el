;; -*- lexical-binding: t -*-
;;; org/org-wild-notifier.el — Wild notifications

(use-package org-wild-notifier
  :after org
  :config
  (setq org-wild-notifier-alert-time '(10 30 60)
        org-wild-notifier-notification-title "lifeos"
        org-wild-notifier-keyword-whitelist nil)
  (org-wild-notifier-mode 1))

