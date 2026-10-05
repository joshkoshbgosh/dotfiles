;; -*- lexical-binding: t -*-
;;; agents/knockknock.el — Knockknock notifications

(use-package knockknock
  :straight (knockknock :type git :host github :repo "konrad1977/knockknock")
  :config
  (setq knockknock-use-svg-layout t)
  (setq knockknock-default-duration 0)
  (setq knockknock-poshandler #'posframe-poshandler-frame-top-center)
  (setq knockknock-background-color "#1e1e2e")
  (setq knockknock-foreground-color "#cdd6f4")
  (setq knockknock-border-color "#89b4fa")
  (setq knockknock-border-width 2))

