;; -*- lexical-binding: t -*-
;;; completion/consult.el --- consult commands and preview

(use-package consult
  :after vertico
  :init
  ;; Auto-preview with debounce (Telescope-like behavior)
  (setq consult-preview-key '(:debounce 0.2 any)))

(with-eval-after-load 'consult
  (my/leader
    "p s" '(consult-ripgrep :which-key "ripgrep (project)")))

