;; -*- lexical-binding: t -*-
;;; org/supertag.el — Supertag + LifeOS rule helpers

(use-package supertag
  :straight (:host github :repo "yibie/supertag")
  :after org
  :commands (supertag-setup supertag-reindex-org supertag-menu supertag-doctor)
  :init
  (setq supertag-data-directory
        (expand-file-name ".supertag/" org-directory))
  (unless (file-directory-p supertag-data-directory)
    (make-directory supertag-data-directory t))
  (defun my/lifeos-supertag-initialize ()
    "Run the Supertag setup wizard for the LifeOS directory."
    (interactive)
    (supertag-setup))

  (defun my/lifeos-supertag-rescan ()
    "Reindex LifeOS files into the Supertag database."
    (interactive)
    (supertag-reindex-org))

  ;; LifeOS automation helpers (used by supertag rules; defined here so
  ;; they survive restarts — rules reference them by symbol).
  (defun my/lifeos-node-refs (node-id field-id)
    "Return NODE-ID's FIELD-ID :node-reference value as a list of IDs."
    (supertag-field-normalize-node-reference-list
     (supertag-node-get-global-field node-id field-id)))

  (defun my/lifeos-task-ids ()
    "Return IDs of all nodes tagged #task."
    (supertag-query-node-ids-by-tag "task"))

  (defun my/lifeos-tasks-referencing (field-id target-id)
    "Return #task node IDs whose FIELD-ID references TARGET-ID."
    (cl-loop for tid in (my/lifeos-task-ids)
             when (member target-id (my/lifeos-node-refs tid field-id))
             collect tid))

  (defun my/lifeos-rollup-task-project (node-id &rest _context)
    "Sum ACTUAL_MINUTES of sibling tasks into their project's TOTAL_MINUTES.
Also refreshes the project's OPEN_TASKS count. Runs when a task's
actual_minutes field changes."
    (dolist (pid (my/lifeos-node-refs node-id "project"))
      (let ((siblings (my/lifeos-tasks-referencing "project" pid))
            (total 0) (open 0))
        (dolist (tid siblings)
          (setq total (+ total (or (supertag-node-get-global-field tid "actual_minutes") 0)))
          (let ((todo (plist-get (supertag-node-get tid) :todo)))
            (unless (member todo '("DONE" "CANCELLED" "CANCELED"))
              (setq open (1+ open)))))
        (supertag-node-set-global-field pid "total_minutes" total)
        (supertag-node-set-global-field pid "open_tasks" open)
        (message "LifeOS: project %s rollup total_minutes=%s open_tasks=%s"
                 pid total open))))

  (defun my/lifeos-task-completed (node-id &rest _context)
    "On task DONE: unblock dependents and maybe complete its project."
    ;; Unblock dependents.
    (dolist (dep-id (my/lifeos-tasks-referencing "blocked_by" node-id))
      (message "LifeOS: %s unblocked by completion of %s"
               (plist-get (supertag-node-get dep-id) :title)
               (plist-get (supertag-node-get node-id) :title)))
    ;; Project completion check.
    (dolist (pid (my/lifeos-node-refs node-id "project"))
      (let ((siblings (my/lifeos-tasks-referencing "project" pid))
            (all-done t))
        (dolist (tid siblings)
          (unless (member (plist-get (supertag-node-get tid) :todo)
                          '("DONE" "CANCELLED" "CANCELED"))
            (setq all-done nil)))
        (when (and all-done siblings)
          (supertag-node-set-global-field pid "status" "Done")
          (message "LifeOS: project %s all tasks done — status set to Done" pid)))))

  (defun my/lifeos-flag-due-reviews (&rest _ignored)
    "List projects whose review is due (for the nightly scheduled rule)."
    (interactive)
    (let ((now (current-time)) (due '()))
      (dolist (nid (supertag-query-node-ids-by-tag "project"))
        (let ((last (supertag-node-get-global-field nid "last_review"))
              (every (supertag-node-get-global-field nid "review_every_days")))
          (when (and last every (> every 0))
            (let ((next (time-add last (days-to-time every))))
              (when (time-less-p next now)
                (push (plist-get (supertag-node-get nid) :title) due))))))
      (if due
          (message "LifeOS: review due for: %s" (string-join due ", "))
        (message "LifeOS: no project reviews due"))))

  (defun my/lifeos-clock-out-rollup ()
    "On clock-out, add clocked minutes to the heading's task ACTUAL_MINUTES.
Fires the rollup rule, so project totals update automatically. No-op
when the clocked heading is not a #task node."
    (when (and (boundp 'org-clock-start-time) org-clock-start-time)
      (let ((mins (round (/ (float-time
                             (time-subtract (current-time) org-clock-start-time))
                            60))))
        (when (and (> mins 0) (org-id-get))
          (let ((node (supertag-node-get (org-id-get))))
            (when (and node (member "task" (plist-get node :tags)))
              (let ((id (plist-get node :id)))
                (supertag-node-set-global-field
                 id "actual_minutes"
                 (+ (or (supertag-node-get-global-field id "actual_minutes") 0)
                    mins))
                (message "LifeOS: +%d min clocked on %s"
                         mins (plist-get node :title)))))))))
    (add-hook 'org-clock-out-hook #'my/lifeos-clock-out-rollup)

  (defun my/lifeos-blocked-tasks ()
    "Return #task nodes that have blockers which are not DONE.
The query grammar cannot test field presence, so this is a helper
for views / reviews. Interactive: lists them in Messages."
    (interactive)
    (let ((blocked '()))
      (dolist (tid (my/lifeos-task-ids))
        (let ((blockers (my/lifeos-node-refs tid "blocked_by")))
          (when (cl-some (lambda (bid)
                         (not (member (plist-get (supertag-node-get bid) :todo)
                                      '("DONE" "CANCELLED" "CANCELED"))))
                       blockers)
            (push tid blocked))))
      (when (called-interactively-p 'any)
        (if blocked
            (message "LifeOS blocked: %s"
                     (string-join (mapcar (lambda (id) (plist-get (supertag-node-get id) :title)) blocked) ", "))
          (message "LifeOS: nothing blocked")))
      blocked))
  :config
  (supertag-smart-key-mode 1)
  ;; Nightly review-nudge rule needs the scheduler running.
  (when (fboundp 'supertag-scheduler-start)
    (supertag-scheduler-start))
  ;; Supertag views define their own single-key keymaps, which Evil's
  ;; normal state shadows (e.g. `a' becoming evil-append). Give every
  ;; supertag view Emacs state instead of mirroring keys one by one --
  ;; this scales to new views without per-key maintenance.
  ;; NOTE: do not use the evil-define-key macro with loop variables
  ;; here; it silently installs nil bindings. evil-set-initial-state
  ;; is a plain function and safe.
  (with-eval-after-load 'evil
    (dolist (mode '(supertag-schema-view-mode
                    supertag-view-table-mode
                    supertag-view-stream-mode
                    supertag-view-node-mode
                    supertag-view-kanban-mode
                    supertag-view-widget-mode))
      (evil-set-initial-state mode 'emacs))))

