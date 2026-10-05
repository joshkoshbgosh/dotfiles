;; -*- lexical-binding: t -*-
;;; org/calfw-org.el — Calendar with org agenda

(use-package calfw-org
  :after (org calfw)
  :config
  (defun my/calfw-open ()
    "Open calfw calendar showing org agenda items."
    (interactive)
    (cfw:open-calendar-buffer
     :contents-sources
     (list (cfw:org-create-source "Green"))))

  )


