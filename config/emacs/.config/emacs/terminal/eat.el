;; -*- lexical-binding: t -*-
;;; terminal/eat.el — Eat integration

(use-package eat
  :commands eat
  :straight (eat :host codeberg :repo "akib/emacs-eat")
  :config
  (add-hook 'eat-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  (with-eval-after-load 'evil
    (evil-set-initial-state 'eat-mode 'emacs)
    (add-hook 'eat-mode-hook #'evil-emacs-state)))

