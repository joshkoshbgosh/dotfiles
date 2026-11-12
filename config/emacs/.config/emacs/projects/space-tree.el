;; -*- lexical-binding: t -*-
;;; projects/space-tree.el --- tree-shaped workspaces (#15)

;; Replaces persp-mode. Each space keeps its own window configuration; spaces
;; nest, so a top-level space per project and sub-spaces per task works.
;; There is no persistence: pair it with bookmark-view for saved views.

(use-package space-tree
  :straight (:host github :repo "chiply/space-tree")
  :demand t
  :init
  ;; First space is 1, not 0.
  (setq space-tree-start-at-0 nil)
  :config
  (space-tree-init)

  (with-eval-after-load 'general
    (my/leader
      "TAB"     '(:ignore t :which-key "workspace")
      "TAB TAB" '(space-tree-switch-space-by-name :which-key "switch by name")
      "TAB n"   '(space-tree-go-right :which-key "next")
      "TAB p"   '(space-tree-go-left :which-key "prev")
      "TAB l"   '(space-tree-go-to-last-space :which-key "last used")
      "TAB c"   '(space-tree-create-space-current-level :which-key "create here")
      "TAB C"   '(space-tree-create-space-top-level :which-key "create top level")
      "TAB k"   '(space-tree-delete-space :which-key "delete"))))
