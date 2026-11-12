;; -*- lexical-binding: t -*-
;;; terminal/ghostel.el — Ghostel integration

;; ghostel already routes `C-c' through Emacs (`ghostel-keymap-exceptions') and
;; binds the comint conventions itself: `C-c C-c' is `ghostel-send-C-c'
;; (interrupt), `C-c C-z' suspend, `C-c C-d' EOF, `C-c C-t' copy mode.  Unused
;; `C-c' continuations fall through to keys/global.el.

(use-package ghostel
  :straight (ghostel :host github :repo "dakra/ghostel")
  :commands ghostel
  :config
  (add-hook 'ghostel-mode-hook (lambda () (display-line-numbers-mode -1)) t))
