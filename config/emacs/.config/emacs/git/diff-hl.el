;; -*- lexical-binding: t -*-
;;; git/diff-hl.el — Git fringe diff highlighting

(use-package diff-hl
  :demand t
  :config
  (global-diff-hl-mode 1)
  (diff-hl-flydiff-mode 1)       ; show unstaged changes without saving
  (add-hook 'dired-mode-hook #'diff-hl-dired-mode-unless-remote) ; fringe indicators in dired
  ;; Keep in sync with magit operations
  (add-hook 'magit-pre-refresh-hook  #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)
  ;; Auto-update after external commits (e.g., from Claude Code / terminal).
  ;; vc-refresh-state fires periodically via auto-revert-check-vc-info.
  (advice-add 'vc-refresh-state :after
              (lambda (&rest _)
                (when (bound-and-true-p diff-hl-mode)
                  (diff-hl-update-once)))))

