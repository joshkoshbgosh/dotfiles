;; -*- lexical-binding: t -*-
;;; agents/agent-shell-manager.el — Agent shell manager

(use-package agent-shell-manager
  :straight (agent-shell-manager
              :type git
              :host github
              :repo "jethrokuan/agent-shell-manager")
  :config
  (setq agent-shell-manager-side 'bottom))

