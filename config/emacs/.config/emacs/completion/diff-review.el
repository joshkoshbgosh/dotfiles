;; -*- lexical-binding: t -*-
;;; completion/diff-review.el --- pull-request style diff review (#5)

;; Reviews a branch or a commit range as a file tree plus the real files in
;; their own major modes. Entry points: `diff-review-branch' and
;; `diff-review-find-file'. In a file, commands are under
;; `diff-review-command-prefix' ("C-c r" here); `M-g n'/`M-g p' walk hunks.

(use-package diff-review
  :straight (:host github :repo "xiaoxinghu/diff-review")
  :after magit
  :custom
  (diff-review-command-prefix "C-c r")
  :config
  ;; Adds the worktrees section to magit-status and "Review" to the diff menu.
  (diff-review-magit-mode 1))
