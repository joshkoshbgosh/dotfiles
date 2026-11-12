;; -*- lexical-binding: t -*-
;;; agents/agent-shell.el — Agent shell integration with advice/debug helpers

;; --- Advice / compat / debug helpers ---
;; These are tightly coupled to agent-shell and must be defined before
;; the use-package block below uses advice-add with them.

(defun my/agent-shell-force-reset ()
  "Force-reset agent-shell busy state when stuck after a failed interrupt."
  (interactive)
  (unless (derived-mode-p 'agent-shell-mode)
    (user-error "Not in an agent-shell buffer"))
  (when (bound-and-true-p shell-maker--busy)
    (shell-maker-interrupt))
  (when (map-nested-elt (agent-shell--state) '(:heartbeat :heartbeat-timer))
    (agent-shell-heartbeat-stop
     :heartbeat (map-elt (agent-shell--state) :heartbeat)))
  (message "Agent shell reset."))

(defun my/agent-shell-session-status ()
  "Show current session info: mode, model, context usage, and busy state."
  (interactive)
  (unless (derived-mode-p 'agent-shell-mode)
    (user-error "Not in an agent-shell buffer"))
  (let* ((state (agent-shell--state))
         (session-id (map-nested-elt state '(:session :id)))
         (mode-id (map-nested-elt state '(:session :mode-id)))
         (model-id (map-nested-elt state '(:set-model)))
         (busy (bound-and-true-p shell-maker--busy))
         (heartbeat-status (map-nested-elt state '(:heartbeat :status))))
    (message "Session: %s | Mode: %s | Busy: %s | Heartbeat: %s%s"
             (or session-id "none")
             (or mode-id "default")
             busy
             (or heartbeat-status "none")
              (if (agent-shell--usage-has-data-p (map-elt state :usage))
                  (format " | %s" (agent-shell--format-usage (map-elt state :usage)))
                ""))))

(defvar my/agent-shell-debug-diffs t
  "When non-nil, log diff extraction details for agent-shell tool calls.")

(defun my/agent-shell--debug-log (format-string &rest args)
  "Append a formatted debug line to the agent-shell diff log buffer."
  (when my/agent-shell-debug-diffs
    (with-current-buffer (get-buffer-create "*agent-shell-diff-debug*")
      (goto-char (point-max))
      (insert (format-time-string "[%F %T] "))
      (insert (apply #'format format-string args))
      (insert "\n"))))

(defun my/agent-shell-open-diff-debug-log ()
  "Open the agent-shell diff debug log buffer."
  (interactive)
  (pop-to-buffer (get-buffer-create "*agent-shell-diff-debug*")))

(defun my/agent-shell-clear-diff-debug-log ()
  "Clear the agent-shell diff debug log buffer."
  (interactive)
  (with-current-buffer (get-buffer-create "*agent-shell-diff-debug*")
    (erase-buffer))
  (message "Cleared *agent-shell-diff-debug*"))

(defun my/agent-shell--map-keys (value)
  "Return VALUE's keys as strings when it looks like a map/alist."
  (cond
   ((vectorp value)
    nil)
   ((listp value)
    (delq nil
          (mapcar (lambda (entry)
                    (when (consp entry)
                      (format "%s" (car entry))))
                  value)))
   (t nil)))

(defun my/agent-shell--content-summary (content)
  "Return a compact summary of CONTENT payload types."
  (cond
   ((null content)
    nil)
   ((vectorp content)
    (mapcar (lambda (item) (map-elt item 'type)) content))
   ((and (listp content)
         (consp content)
         (assoc 'type content))
    (list (map-elt content 'type)))
   ((listp content)
    (mapcar (lambda (item)
              (when (listp item)
                (map-elt item 'type)))
            content))
   (t
    (list (format "%s" (type-of content))))))

(defun my/agent-shell--debug-make-diff-info (fn &rest args)
  "Log `agent-shell--make-diff-info' inputs and outputs around FN."
  (let* ((acp-tool-call (plist-get args :acp-tool-call))
         (raw-input (map-elt acp-tool-call 'rawInput))
         (content (map-elt acp-tool-call 'content))
         (result (apply fn args)))
    (my/agent-shell--debug-log
     "make-diff-info title=%S kind=%S status=%S content-types=%S raw-input-keys=%S flags=%S result-keys=%S"
     (map-elt acp-tool-call 'title)
     (map-elt acp-tool-call 'kind)
     (map-elt acp-tool-call 'status)
     (my/agent-shell--content-summary content)
     (my/agent-shell--map-keys raw-input)
     `((patchText . ,(and raw-input (map-elt raw-input 'patchText) t))
       (diff . ,(and raw-input (map-elt raw-input 'diff) t))
       (new_str . ,(and raw-input (map-elt raw-input 'new_str) t))
       (newString . ,(and raw-input (map-elt raw-input 'newString) t))
       (newText . ,(and raw-input (map-elt raw-input 'newText) t)))
     (my/agent-shell--map-keys result))
    (when (and raw-input
               (or (map-elt raw-input 'patchText)
                   (map-elt raw-input 'diff)
                   (map-elt raw-input 'new_str)
                   (map-elt raw-input 'newString)
                   (map-elt raw-input 'newText))
               (null result))
      (my/agent-shell--debug-log
       "raw-input=%S content=%S"
       raw-input
       content))
    result))

(defun my/agent-shell--make-diff-info-compat (fn &rest args)
  "Extend `agent-shell--make-diff-info' for OpenCode diff payloads.

  This fills the current gaps in upstream `agent-shell':
  - `rawInput.filepath' instead of `path' or `fileName'
  - `rawInput.patchText' from `apply_patch'

  It defers to upstream first and only synthesizes a diff when upstream
  returns nil."
  (or (apply fn args)
      (let* ((acp-tool-call (plist-get args :acp-tool-call))
             (raw-input (map-elt acp-tool-call 'rawInput))
             (patch-text (and raw-input (map-elt raw-input 'patchText)))
             (diff-text (and raw-input (map-elt raw-input 'diff)))
             (file-path (and raw-input
                             (or (map-elt raw-input 'filepath)
                                 (map-elt raw-input 'filePath)
                                 (map-elt raw-input 'path)
                                 (map-elt raw-input 'fileName))))
             (parsed (cond
                      (patch-text
                       (agent-shell--parse-unified-diff patch-text))
                      (diff-text
                       (agent-shell--parse-unified-diff diff-text)))))
        (when (and parsed file-path)
          (list (cons :old (car parsed))
                (cons :new (cdr parsed))
                (cons :file file-path))))))

(defun my/agent-shell--inline-permission-diff (fn &rest args)
  "Append inline diff text to tool permission prompts when available."
  (let* ((body (apply fn args))
         (acp-request (plist-get args :acp-request))
         (state (plist-get args :state))
         (tool-call-id (map-nested-elt acp-request '(params toolCall toolCallId)))
         (diff (and state tool-call-id
                    (map-nested-elt state `(:tool-calls ,tool-call-id :diff))))
         (diff-text (and diff (agent-shell--format-diff-as-text diff))))
    (if diff-text
        (concat
          "    \n"
          "    ╭─────────╮\n"
          "    │ changes │\n"
          "    ╰─────────╯\n\n"
          (replace-regexp-in-string "^" "    " diff-text)
          "\n\n"
          body)
      body)))

(defun my/agent-shell--hide-view-diff-button (fn &rest args)
  "Hide the visible `View (v)' button from permission prompts.

  Upstream still wires the `v' action into the permission keymap, but this keeps
  the button itself out of the rendered prompt so inline diffs are the only
  visible affordance."
  (let ((body (apply fn args)))
    (replace-regexp-in-string
     "[[:space:]]*\\[ View (v) \\][[:space:]]*"
     " "
     body)))

(defun my/agent-shell--suppress-view-diff-button (fn &rest args)
  "Return no visible button for the upstream `view diff' permission action."
  (if (equal (plist-get args :option) "view diff")
      ""
    (apply fn args)))

(defvar my/agent-shell-permission-feedback-kinds '("edit" "write")
  "Tool call kinds that should offer optional feedback after permission choices.")

(defvar my/agent-shell-permission-actions (make-hash-table :test 'equal)
  "Permission actions keyed by shell buffer, request id, and tool call id.")

(defun my/agent-shell--permission-action-key (&key state request-id tool-call-id)
  "Build the lookup key for a permission action set."
  (list (map-elt state :buffer) request-id tool-call-id))

(defun my/agent-shell--remember-permission-actions (fn &rest args)
  "Remember permission actions before FN renders the default permission UI."
  (when-let* ((acp-request (plist-get args :acp-request))
              (state (plist-get args :state))
              (request-id (map-elt acp-request 'id))
              (tool-call-id (map-nested-elt acp-request '(params toolCall toolCallId))))
    (puthash (my/agent-shell--permission-action-key
              :state state :request-id request-id :tool-call-id tool-call-id)
             (agent-shell--make-permission-actions
              (map-nested-elt acp-request '(params options)))
             my/agent-shell-permission-actions))
  (apply fn args))

(defun my/agent-shell--queue-permission-feedback (buffer prompt)
  "Prompt for optional feedback and submit it to BUFFER."
  (let ((feedback (read-string prompt)))
    (when (and (buffer-live-p buffer)
               (not (string-empty-p feedback)))
      (run-at-time 0.2 nil
                   (lambda (shell-buffer msg)
                     (when (buffer-live-p shell-buffer)
                       (with-current-buffer shell-buffer
                         (agent-shell-insert :text msg :submit t))))
                   buffer feedback))))

(defun my/agent-shell--permission-feedback-response (fn &rest args)
  "After FN resolves a permission, optionally collect feedback for edit/write actions."
  (let* ((state (plist-get args :state))
         (request-id (plist-get args :request-id))
         (tool-call-id (plist-get args :tool-call-id))
         (option-id (plist-get args :option-id))
         (cancelled (plist-get args :cancelled))
         (key (and state request-id tool-call-id
                   (my/agent-shell--permission-action-key
                    :state state :request-id request-id :tool-call-id tool-call-id)))
         (actions (and key (gethash key my/agent-shell-permission-actions)))
         (action (and option-id
                      (seq-find (lambda (candidate)
                                  (equal (map-elt candidate :option-id) option-id))
                                actions)))
         (action-kind (map-elt action :kind))
         (tool-kind (and state tool-call-id
                         (map-nested-elt state `(:tool-calls ,tool-call-id :kind))))
         (tool-title (and state tool-call-id
                          (map-nested-elt state `(:tool-calls ,tool-call-id :title))))
         (buffer (and state (map-elt state :buffer))))
    (unwind-protect
        (prog1 (apply fn args)
          (when (and (not cancelled)
                     (member tool-kind my/agent-shell-permission-feedback-kinds)
                     (member action-kind '("allow_once" "reject_once"))
                     (buffer-live-p buffer))
            (my/agent-shell--queue-permission-feedback
             buffer
             (format "%s feedback for %s (optional): "
                     (if (string= action-kind "allow_once") "Accept" "Reject")
                     (or tool-title tool-kind)))))
      (when key
        (remhash key my/agent-shell-permission-actions)))))

(use-package agent-shell
  :commands (agent-shell
             agent-shell-opencode-start-agent
             agent-shell-anthropic-start-claude-code
             agent-shell-toggle
             agent-shell-send-region
             agent-shell-send-file)
  :init
  (setq agent-shell-anthropic-default-session-mode-id "code"
        agent-shell-show-usage-at-turn-end t
        agent-shell-show-context-usage-indicator 'detailed
        agent-shell-prefer-viewport-interaction nil
        agent-shell-thought-process-expand-by-default t
        agent-shell-tool-use-expand-by-default t)
  :config
  (setq agent-shell-permission-responder-function nil)
  (advice-remove 'agent-shell--make-diff-info #'my/agent-shell--make-diff-info-compat)
  (advice-add 'agent-shell--make-diff-info :around #'my/agent-shell--make-diff-info-compat)
  (advice-remove 'agent-shell--make-diff-info #'my/agent-shell--debug-make-diff-info)
  (advice-add 'agent-shell--make-diff-info :around #'my/agent-shell--debug-make-diff-info)
  (advice-remove 'agent-shell--make-tool-call-permission-text #'my/agent-shell--hide-view-diff-button)
  (advice-add 'agent-shell--make-tool-call-permission-text :around #'my/agent-shell--hide-view-diff-button)
  (advice-remove 'agent-shell--make-permission-button #'my/agent-shell--suppress-view-diff-button)
  (advice-add 'agent-shell--make-permission-button :around #'my/agent-shell--suppress-view-diff-button)
  ;; Feedback advice disabled for now - it hangs when read-string runs during busy state
  ;; (advice-remove 'agent-shell--make-tool-call-permission-text #'my/agent-shell--remember-permission-actions)
  ;; (advice-add 'agent-shell--make-tool-call-permission-text :around #'my/agent-shell--remember-permission-actions)
  ;; (advice-remove 'agent-shell--send-permission-response #'my/agent-shell--permission-feedback-response)
  ;; (advice-add 'agent-shell--send-permission-response :around #'my/agent-shell--permission-feedback-response)
  (add-hook 'agent-shell-mode-hook (lambda () (display-line-numbers-mode -1)) t)
  (with-eval-after-load 'evil
    (evil-define-key 'insert agent-shell-mode-map (kbd "RET") #'newline)
    (evil-define-key 'normal agent-shell-mode-map (kbd "RET") #'comint-send-input)
    (add-hook 'diff-mode-hook
              (lambda ()
                (when (string-match-p "\\*agent-shell-diff\\*" (buffer-name))
                  (evil-emacs-state))))
    (dolist (state '(normal motion))
      (evil-define-key state agent-shell-mode-map
        (kbd "C-c C-k") #'my/agent-shell-force-reset)))
  (define-key agent-shell-mode-map (kbd "C-c C-k") #'my/agent-shell-force-reset))

