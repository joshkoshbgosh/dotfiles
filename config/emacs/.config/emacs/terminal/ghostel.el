;; -*- lexical-binding: t -*-
;;; terminal/ghostel.el — Ghostel integration

(use-package ghostel
  :straight (ghostel :host github :repo "dakra/ghostel")
  :commands ghostel
  :config
  (add-hook 'ghostel-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  (with-eval-after-load 'evil
    (evil-set-initial-state 'ghostel-mode 'emacs)
    (add-hook 'ghostel-mode-hook #'evil-emacs-state)))

