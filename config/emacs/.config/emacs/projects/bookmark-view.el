;; -*- lexical-binding: t -*-
;;; projects/bookmark-view.el --- persist window configurations as bookmarks (#15)

;; `bookmark-view' saves the current window configuration under a bookmark
;; name and restores it later; `bookmark-view-push'/`-pop' keep a stack.
;; This is what replaces persp-mode's autosaved sessions.

(use-package bookmark-view
  :straight (:host github :repo "minad/bookmark-view")
  :bind ("C-x r v" . bookmark-view))
