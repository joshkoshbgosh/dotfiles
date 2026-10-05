;; -*- lexical-binding: t -*-
;;; org/org-pomodoro.el — Pomodoro timer

(use-package org-pomodoro
  :after org
  :config
  (setq org-pomodoro-length 25
        org-pomodoro-short-break-length 5
        org-pomodoro-long-break-length 15
        org-pomodoro-long-break-frequency 4))

