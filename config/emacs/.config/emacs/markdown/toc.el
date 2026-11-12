;; -*- lexical-binding: t -*-
;;; markdown/toc.el — table of contents for markdown files

;; markdown-mode has no TOC support of its own.  `markdown-toc' builds one from
;; imenu, with GitHub-style anchors, and replaces an existing TOC between its
;; `<!-- toc -->' markers instead of appending a second one.
;;
;; Commands are bound in my/markdown-command-map: `C-c m t' generate/refresh,
;; `C-c m d' delete.  The package is not loaded until one of them is used.

(use-package markdown-toc
  :after markdown-mode
  :commands (markdown-toc-generate-or-refresh-toc
             markdown-toc-generate-toc
             markdown-toc-refresh-toc
             markdown-toc-delete-toc))
