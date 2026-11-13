;; -*- lexical-binding: t -*-
;;; completion/combobulate.el --- combobulate structured editing/navigation

;;; Commentary:
;; combobulate provides tree-sitter-driven structural navigation and editing.
;; The package is registered and built eagerly in startup/straight.el; this
;; only declares the (deferred) use-package entry.
;;
;; NB: `straight-use-package' takes (RECIPE &optional no-clone no-build ...),
;; not use-package keywords.  The previous
;;   (straight-use-package 'combobulate :config (combobulate-mode 1))
;; bound `:config' to NO-CLONE, which made straight register the recipe and
;; stop: no build, no autoload and no `combobulate-mode'.
;;
;; `combobulate-mode' in this package is a command, not a real minor mode
;; (see `combobulate-maybe-activate'), so its own recommended entry point is
;; typing it per buffer.  With `use-package-always-defer' set, `:commands' is
;; what makes that work without loading the package at startup.  To enable it
;; automatically instead, hook it, e.g.:
;;   (add-hook 'prog-mode-hook #'combobulate-mode)

;;; Code:
(use-package combobulate
  :straight t
  :commands (combobulate-mode))
