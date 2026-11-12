;; -*- lexical-binding: t -*-
;;; terminal/vterm.el — Vterm configuration

;; `C-c' is sent to the shell inside vterm, so the personal `C-c' bindings in
;; keys/global.el are not reachable here; use `M-x' in a terminal buffer.

(use-package vterm
  :commands vterm
  :config
  (add-hook 'vterm-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  (with-eval-after-load 'evil
    ;; Keep terminal buffers in emacs state so TUI keybindings pass through.
    (evil-set-initial-state 'vterm-mode 'emacs)
    (add-hook 'vterm-mode-hook #'evil-emacs-state)))
