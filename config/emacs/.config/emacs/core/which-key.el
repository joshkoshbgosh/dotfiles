;; -*- lexical-binding: t -*-
;;; core/which-key.el --- keybinding discoverability
;;; test
;;; testing test

(use-package which-key
  :demand t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.25
        which-key-idle-secondary-delay 0.05
        which-key-sort-order 'which-key-key-order
        which-key-show-remaining-keys t))

