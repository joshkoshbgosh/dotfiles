;; -*- lexical-binding: t -*-
;;; markdown/overlays.el — inline rendering for markdown buffers

;; `markdown-overlays' ships inside shell-maker (installed for agent-shell) and
;; is not markdown-mode specific: it scans the buffer for markdown syntax and
;; adds `display' overlays — scaled headings, real tables, highlighted fenced
;; code, clickable links, inline images.  That is exactly the "show me the
;; rendered thing without leaving Emacs" half of the markdown stack; the
;; preview/export half lives in markdown-mode.el.
;;
;; Opt-in per buffer (`C-c m o').  The overlays are recomputed on save, not on
;; every keystroke: parsing the whole buffer on each change is noticeable in
;; long documents and buys nothing you can see while typing.

(defvar-local my/markdown-overlays-active nil
  "Non-nil when inline markdown overlays are displayed in this buffer.")

(defun my/markdown-overlays--refresh (&rest _)
  "Recompute the inline overlays of the current buffer."
  (when (and my/markdown-overlays-active (derived-mode-p 'markdown-mode))
    (markdown-overlays-remove)
    (markdown-overlays-put)))

(defun my/markdown-overlays-toggle ()
  "Toggle inline rendering of the markdown buffer at point.

With overlays on, headings, tables, code fences, links and images are
displayed rendered instead of as markup; the buffer text is untouched."
  (interactive)
  (require 'markdown-overlays)
  (setq my/markdown-overlays-active (not my/markdown-overlays-active))
  (if my/markdown-overlays-active
      (progn
        (my/markdown-overlays--refresh)
        (add-hook 'after-save-hook #'my/markdown-overlays--refresh nil t)
        (message "Inline markdown rendering on"))
    (markdown-overlays-remove)
    (remove-hook 'after-save-hook #'my/markdown-overlays--refresh t)
    (message "Inline markdown rendering off")))
