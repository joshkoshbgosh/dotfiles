;; -*- lexical-binding: t -*-
;;; agents/meta-agent-shell.el — Meta agent shell

(use-package meta-agent-shell
  :straight (meta-agent-shell
              :type git
              :host github
              :repo "ElleNajt/meta-agent-shell")
  :after agent-shell
  :config
  (setq meta-agent-shell-heartbeat-file "~/heartbeat.org")
  (setq meta-agent-shell-start-function #'agent-shell))

