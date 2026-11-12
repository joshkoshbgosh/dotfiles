;; -*- lexical-binding: t -*-
;;; projects/agent-shell-links.el --- stable links to agent sessions (#15)

;; Mirrors space-tree's lack of persistence for agent buffers: a session can be
;; bookmarked and linked from org, and reopening it resumes the session.
;; Loading the package only defines functions, so both setups are called here.

(use-package agent-shell-links
  :straight (:host github :repo "ultronozm/agent-shell-links.el")
  :after agent-shell
  :config
  (agent-shell-links-bookmark-setup)
  (with-eval-after-load 'ol
    (org-link-set-parameters "agent-shell"
                             :follow #'agent-shell-links-org-follow
                             :store #'agent-shell-links-org-store)))
