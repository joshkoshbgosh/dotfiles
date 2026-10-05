;; -*- lexical-binding: t -*-
;;; agents/agent-shell-notifications.el — Agent shell notifications

(use-package agent-shell-notifications
  :straight (agent-shell-notifications
              :type git
              :host github
              :repo "zackattackz/agent-shell-notifications")
  :hook
  (agent-shell-mode . agent-shell-notifications-mode)
  :config
  (setq agent-shell-notifications-idle-timeout 10)
  (setq agent-shell-notifications-timeout 0)
  (setq agent-shell-notifications-provider 'agent-shell-notifications-knockknock))

(defun my/agent-shell-notifications-format (type event)
  "Custom notification format with different icons per event type."
  (pcase type
    ('turn-complete (list :title "Agent Ready" :icon "cod-check" :body (format "Response ready: %s" (cdr (assoc-default 'text event)))))
    ('permission-request (list :title "Permission Needed" :icon "cod-question" :body (format "%s" (cdr (assoc-default 'text event)))))
    ('error (list :title "Agent Error" :icon "cod-error" :body (format "Error: %s" (cdr (assoc-default 'message event)))))
    (_ (list :title "Agent" :icon "cod-comment-discussion" :body (format "%s" (cdr (assoc-default 'text event)))))))

(setq agent-shell-notifications-format-function #'my/agent-shell-notifications-format)


