;; -*- lexical-binding: t -*-
;;; agents/agent-shell-knockknock.el — Agent shell knockknock integration

(use-package agent-shell-knockknock
  :straight (agent-shell-knockknock
              :type git
              :host github
              :repo "xenodium/agent-shell-knockknock")
  :after (agent-shell knockknock)
  :hook (agent-shell-mode . agent-shell-knockknock-mode))

