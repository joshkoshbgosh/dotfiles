;; -*- lexical-binding: t -*-
;;; terminal/vterm.el — Vterm configuration

;; vterm keeps `C-c' out of its keymap on purpose
;; (`vterm-keymap-exceptions'), so `C-c' is an Emacs prefix inside a vterm
;; buffer: `C-c C-c' stays `vterm--self-insert' (which sends 0x03, SIGINT)
;; and everything else falls through to the table in keys/global.el.

(use-package vterm
  :commands vterm
  :config
  (add-hook 'vterm-mode-hook (lambda () (display-line-numbers-mode -1)) t))
