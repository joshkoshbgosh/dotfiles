;; -*- lexical-binding: t -*-
;;; terminal/vterm.el — Vterm configuration

(use-package vterm
  :commands vterm
  :config
  (add-hook 'vterm-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  ;; Override vterm's meta-key catch-all so M-; (leader) reaches general.
  ;; Must append (t) so it runs after vterm-mode finishes binding keys.
  (add-hook 'vterm-mode-hook
    (lambda ()
      (define-key vterm-mode-map (kbd "M-;")
        (lookup-key (evil-get-auxiliary-keymap general-override-mode-map 'normal t)
                    (kbd "M-;"))))
    t)
  (with-eval-after-load 'evil
    ;; Keep terminal buffers in emacs state so TUI keybindings pass through.
    (evil-set-initial-state 'vterm-mode 'emacs)
    (add-hook 'vterm-mode-hook #'evil-emacs-state))
)


