;; -*- lexical-binding: t -*-
;;; themes/modus-themes.el — Modus themes

(use-package modus-themes
  :straight (:type built-in)
  :init
  ;; High contrast defaults
  (setq modus-themes-bold-constructs t
        modus-themes-italic-constructs t
        modus-themes-mixed-fonts t
        modus-themes-prompts '(bold intense)))

