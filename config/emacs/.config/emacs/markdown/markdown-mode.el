;; -*- lexical-binding: t -*-
;;; markdown/markdown-mode.el — Markdown mode

;; Rendering command for preview/export.  All of these read the buffer on
;; stdin and write an HTML fragment on stdout, which is what `markdown-mode'
;; expects.  pandoc comes first because it is the only one here that renders
;; GFM tables; md4c's `md2html' is CommonMark only, so tables in an exported
;; file degrade to paragraph text (inline tables still render via
;; `markdown-overlays').  The last fallback is markdown-mode's own default so a
;; missing renderer produces its usual error instead of a silently wrong one.
(defvar my/markdown-command
  (cond ((executable-find "pandoc") "pandoc -f gfm -t html")
        ((executable-find "cmark-gfm") "cmark-gfm")
        ((executable-find "md2html") "md2html")
        ((executable-find "cmark") "cmark")
        (t "markdown"))
  "Shell command used by `markdown-preview' and `markdown-export'.")

;; `C-c m' inside markdown buffers only, so it cannot collide with the global
;; C-c table (which has no `C-c m' either).  Two commands live in sibling
;; modules; binding them here by symbol keeps the whole prefix in one place.
(defvar my/markdown-command-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "p" #'markdown-preview)
    (keymap-set map "l" #'markdown-live-preview-mode)
    (keymap-set map "e" #'markdown-export)
    (keymap-set map "o" #'my/markdown-overlays-toggle)
    (keymap-set map "t" #'markdown-toc-generate-or-refresh-toc)
    (keymap-set map "d" #'markdown-toc-delete-toc)
    map)
  "Prefix map for markdown commands, on `C-c m'.")

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :init
  (setq markdown-fontify-code-blocks-natively t
        markdown-hide-markup nil
        markdown-command my/markdown-command)
  :config
  ;; Scale headers without touching colors — let the active theme decide
  (dolist (spec '((markdown-header-face-1 . 1.4)
                  (markdown-header-face-2 . 1.3)
                  (markdown-header-face-3 . 1.2)
                  (markdown-header-face-4 . 1.1)))
    (set-face-attribute (car spec) nil
                        :height (cdr spec)
                        :weight 'bold))
  (keymap-set markdown-mode-map "C-c m" my/markdown-command-map))
