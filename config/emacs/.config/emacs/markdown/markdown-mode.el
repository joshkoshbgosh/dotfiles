;; -*- lexical-binding: t -*-
;;; markdown/markdown-mode.el — Markdown mode

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :init
  (setq markdown-fontify-code-blocks-natively t
        markdown-hide-markup nil)
  :config
  ;; Scale headers without touching colors — let the active theme decide
  (dolist (spec '((markdown-header-face-1 . 1.4)
                  (markdown-header-face-2 . 1.3)
                  (markdown-header-face-3 . 1.2)
                  (markdown-header-face-4 . 1.1)))
    (set-face-attribute (car spec) nil
                        :height (cdr spec)
                        :weight 'bold)))

