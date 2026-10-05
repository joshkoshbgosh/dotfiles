;; -*- lexical-binding: t -*-
;;; evil/evil.el --- Evil vim emulation

(use-package evil
  :demand t
  :init
  (setq evil-want-keybinding nil
        evil-want-integration t
        evil-respect-visual-line-mode t
        evil-undo-system 'undo-fu)
  :config
  (evil-mode 1))

