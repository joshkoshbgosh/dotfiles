;; -*- lexical-binding: t -*-
;;; terminal/eat.el — Eat integration

;; eat uses `C-c' as its Emacs prefix in every input mode and claims only
;; `C-c C-x'/`C-c M-x' continuations, so the bindings in keys/global.el reach
;; the buffer unchanged.  `C-c C-c' is the interrupt:
;;   semi-char mode (default)  `eat-self-input'       (sends 0x03)
;;   line mode                 `eat-line-send-interrupt'
;;   emacs mode                otherwise unbound, so bind it here; the
;;                             semi-char and line maps are minor/input maps and
;;                             still take precedence over this major-map entry.

(use-package eat
  :commands eat
  :straight (eat :host codeberg :repo "akib/emacs-eat")
  :config
  (add-hook 'eat-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  (keymap-set eat-mode-map "C-c C-c" #'eat-line-send-interrupt))
