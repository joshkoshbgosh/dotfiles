;; -*- lexical-binding: t -*-
;;; projects/space-tree.el --- tree-shaped workspaces (#15)

;; Replaces persp-mode. Each space keeps its own window configuration; spaces
;; nest, so a top-level space per project and sub-spaces per task works.
;; There is no persistence: pair it with bookmark-view for saved views.
;;
;; Commands are bound in keys/global.el (`C-c TAB', `C-c [', `C-c ]').

(use-package space-tree
  :straight (:host github :repo "chiply/space-tree")
  :demand t
  :init
  ;; First space is 1, not 0.
  (setq space-tree-start-at-0 nil)
  :config
  (space-tree-init))
