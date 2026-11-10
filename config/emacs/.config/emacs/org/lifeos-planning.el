;; -*- lexical-binding: t -*-
;;; org/lifeos-planning.el --- LifeOS task metadata helpers

(require 'org)
(require 'org-element)
(require 'org-id)
(require 'org-clock)
(require 'calendar)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defgroup my/lifeos nil
  "LifeOS planning and solver preferences.

These values are implementation fallbacks.  Authoritative recurring and
weekly planning policy remains in planning.org."
  :group 'org
  :prefix "my/lifeos-")

(defconst my/lifeos-impact-values '("High" "Medium" "Low"))
(defconst my/lifeos-work-mode-values '("Deep" "Shallow" "Errand" "Social"))
(defconst my/lifeos-priority-values '("A" "B" "C" "D"))
(defconst my/lifeos-estimate-confidence-values '("Low" "Medium" "High"))

(defcustom my/lifeos-auto-scaffold-tasks t
  "When non-nil, scaffold #task headings after editing and before saving."
  :type 'boolean
  :group 'my/lifeos)

(defcustom my/lifeos-auto-scaffold-projects t
  "When non-nil, scaffold explicit #project headings after editing and before saving."
  :type 'boolean
  :group 'my/lifeos)

(defcustom my/lifeos-project-analysis-idle-delay 0.75
  "Idle seconds before rebuilding cached project planning analysis."
  :type 'number
  :group 'my/lifeos)

(defvar my/lifeos-project-analysis-cache nil
  "Last shared graph, forecast, and project-summary snapshot.")

(defvar my/lifeos-project-analysis-stale t
  "Non-nil when `my/lifeos-project-analysis-cache' needs rebuilding.")

(defvar my/lifeos-project-analysis-timer nil
  "Pending idle timer for rebuilding project analysis.")

(setq org-priority-highest ?A
      org-priority-lowest ?D
      org-priority-default ?C)

(dolist (property `(("IMPACT_ALL" . ,(string-join my/lifeos-impact-values " "))
                    ("WORK_MODE_ALL" . ,(string-join my/lifeos-work-mode-values " "))
                    ("DEFAULT_WORK_MODE_ALL" . ,(string-join my/lifeos-work-mode-values " "))
                    ("ESTIMATE_CONFIDENCE_ALL" . ,(string-join my/lifeos-estimate-confidence-values " "))))
  (setf (alist-get (car property) org-global-properties nil nil #'equal)
        (cdr property)))

(defun my/lifeos--heading-has-supertag-p (tag)
  "Return non-nil when the current heading contains #TAG."
  (let ((heading (org-get-heading t t t t)))
    (string-match-p
     (format "\\(?:\\`\\|[[:space:]]\\)#%s\\(?:\\'\\|[[:space:]]\\)"
             (regexp-quote tag))
     heading)))

(defun my/lifeos--add-heading-supertag (tag)
  "Add #TAG to the current heading unless it is already present."
  (unless (my/lifeos--heading-has-supertag-p tag)
    (org-edit-headline
     (concat (string-trim-right (org-get-heading t t t t)) " #" tag))))

(defun my/lifeos--entry-section-bounds ()
  "Return bounds of the current heading's direct section."
  (save-excursion
    (org-back-to-heading t)
    (let* ((headline (org-element-at-point))
           (start (org-element-property :contents-begin headline))
           (contents-end (org-element-property :contents-end headline)))
      (when (and start contents-end)
        (goto-char start)
        (cons start
              (if (re-search-forward org-outline-regexp-bol contents-end t)
                  (match-beginning 0)
                contents-end))))))

(defun my/lifeos--own-body-has-dependency-p ()
  "Return non-nil when the current heading body has a depends-on link."
  (when-let* ((bounds (my/lifeos--entry-section-bounds)))
    (save-excursion
      (goto-char (car bounds))
      (re-search-forward "\\[\\[depends-on:[^]]+\\]" (cdr bounds) t))))

(defun my/lifeos--dependency-targets ()
  "Return depends-on target IDs from the current heading's own body."
  (when-let* ((bounds (my/lifeos--entry-section-bounds)))
    (save-excursion
      (let (targets)
        (goto-char (car bounds))
        (while (re-search-forward "\\[\\[depends-on:\\([^]]+\\)\\]"
                                  (cdr bounds) t)
          (push (match-string-no-properties 1) targets))
        (nreverse targets)))))

(defun my/lifeos--waiting-reason-p ()
  "Return non-nil when the current heading has an explicit waiting reason."
  (or (my/lifeos--own-body-has-dependency-p)
      (org-entry-get nil "WAIT_UNTIL")
      (org-entry-get nil "WAITING_FOR")))

(defun my/lifeos--valid-effort-p (value)
  "Return non-nil when VALUE is an H:MM duration."
  (and value (string-match-p "\\`[0-9]+:[0-5][0-9]\\'" value)))

(defun my/lifeos--diagnostic (code severity message &optional data)
  "Return a LifeOS diagnostic with CODE, SEVERITY, MESSAGE, and DATA."
  (list :code code :severity severity :message message :data data))

(defconst my/lifeos-diagnostic-severity-order '(error review conflict))

(defconst my/lifeos-diagnostic-severity-faces
  '((error . error) (review . warning) (conflict . font-lock-warning-face)))

(defconst my/lifeos-diagnostic-remediations
  '((non-leaf-task
     "Executable tasks must not contain TODO descendants."
     "Run my/lifeos-break-down-task or make the heading a plain container.")
    (not-active-state
     "LifeOS task validation applies only to active task states."
     "Choose TODO, NEXT, WAITING, or SOMEDAY, or remove #task.")
    (missing-task-tag
     "Active work must be explicitly marked as executable LifeOS work."
     "Run my/lifeos-scaffold-task or add #task.")
    (missing-id
     "Dependencies and cross-file references require stable identity."
     "Run my/lifeos-scaffold-task to create an ID.")
    (invalid-impact
     "Impact is required for task ordering."
     "Set IMPACT to High, Medium, or Low.")
    (missing-dependency-target
     "The dependency link points to an ID that Org cannot resolve."
     "Repair or remove the depends-on link.")
    (invalid-priority
     "Native Org priority participates in forecast ordering."
     "Set priority to A, B, C, or D.")
    (invalid-work-mode
     "A work mode is required to select compatible availability."
     "Set WORK_MODE to Deep, Shallow, Errand, or Social.")
    (invalid-effort
     "Current expected total effort is missing or malformed."
     "Set EFFORT using H:MM.")
    (invalid-original-effort
     "The first accepted estimate must remain available for review."
     "Set ORIGINAL_EFFORT using H:MM.")
    (estimate-exhausted
     "Clocked work has reached or exceeded the current total estimate."
     "Run my/lifeos-set-remaining-effort to re-estimate future work.")
    (missing-waiting-reason
     "WAITING work must state what prevents execution."
     "Add depends-on, WAIT_UNTIL, or WAITING_FOR.")
    (invalid-fixed-schedule
     "A committed fixed start must include a clock time."
     "Add HH:MM to SCHEDULED or remove it as a fixed commitment.")
    (invalid-dependency-graph
     "The dependency graph cannot produce a reliable schedule."
     "Resolve missing, inactive, invalid, or cyclic dependencies.")
    (waiting-not-scheduled
     "WAITING work is represented but is not automatically allocated."
     "Resolve its waiting reason before moving it to TODO or NEXT.")
    (unscheduled-prerequisite
     "A prerequisite could not be placed in the forecast."
     "Explain the prerequisite and correct its planning conflict first.")
    (invalid-scheduling-data
     "The task lacks usable duration or work-mode data."
     "Correct its task diagnostics and rebuild the forecast.")
    (fixed-before-prerequisite
     "The committed start occurs before a prerequisite can finish."
     "Move the fixed start or change the dependency.")
    (fixed-availability-conflict
     "The committed block overlaps unavailable or busy time."
     "Move the fixed start or update availability/calendar data.")
    (fixed-misses-deadline
     "The committed block completes after its effective deadline."
     "Move, shorten, split, or renegotiate the work.")
    (fixed-outside-horizon
     "The committed start is outside the current four-week forecast."
     "Use a wider report when reviewing this later commitment.")
    (no-contiguous-window
     "No compatible availability window is large enough."
     "Split the task into smaller executable leaves.")
    (no-window-before-deadline
     "No compatible window remains before the deadline."
     "Change scope, availability, dependencies, or the deadline.")
     (no-window-in-horizon
      "No compatible window exists in the forecast horizon."
      "Add compatible availability or defer the task.")
     (missing-project-id
      "Projects need stable identity for reports and attribution."
      "Run my/lifeos-groom-project to create an ID.")
     (invalid-project-deadline
      "A project needs a parseable completion boundary."
      "Run my/lifeos-groom-project and enter a project deadline.")
     (invalid-project-effort
      "The project effort envelope is missing or malformed."
      "Run my/lifeos-groom-project and enter a positive 15-minute-aligned duration.")
     (project-effort-overallocated
      "Executable descendant estimates exceed the project effort envelope."
      "Increase PROJECT_EFFORT or revise descendant estimates.")
     (unresolved-descendant-work
      "Active descendant work is not represented by valid executable task leaves."
      "Visit the affected headings and run my/lifeos-groom-task or break down aggregates.")
     (invalid-default-work-mode
      "Unallocated project effort needs a supported work mode."
      "Run my/lifeos-groom-project and choose a usual work mode.")
     (invalid-planning-chunk
      "Virtual project work needs a usable chunk size."
      "Run my/lifeos-groom-project and enter a positive 15-minute-aligned chunk.")
     (invalid-estimate-confidence
      "Virtual project work needs an estimate-confidence label."
      "Run my/lifeos-groom-project and choose Low, Medium, or High.")))

(defun my/lifeos--diagnostics-with-severity (diagnostics severity)
  "Return DIAGNOSTICS whose severity is SEVERITY."
  (seq-filter (lambda (diagnostic)
                (eq (plist-get diagnostic :severity) severity))
              diagnostics))

(defun my/lifeos--diagnostics-have-severity-p (diagnostics severity)
  "Return non-nil when DIAGNOSTICS contains SEVERITY."
  (seq-some (lambda (diagnostic)
              (eq (plist-get diagnostic :severity) severity))
            diagnostics))

(defun my/lifeos--diagnostic-label-string (diagnostics)
  "Return explicit transient severity labels for DIAGNOSTICS."
  (concat
   " "
   (mapconcat
    (lambda (severity)
      (let ((count (length (my/lifeos--diagnostics-with-severity
                            diagnostics severity))))
        (when (> count 0)
          (propertize (format "[%s %d]" (upcase (symbol-name severity)) count)
                      'face (alist-get severity
                                       my/lifeos-diagnostic-severity-faces)))))
    (seq-filter (lambda (severity)
                  (my/lifeos--diagnostics-have-severity-p diagnostics severity))
                my/lifeos-diagnostic-severity-order)
    " ")
   " "))

(defun my/lifeos--diagnostic-help (diagnostics)
  "Return hover text for DIAGNOSTICS including stable reason codes."
  (mapconcat
   (lambda (diagnostic)
     (format "[%s %s] %s"
             (upcase (symbol-name (plist-get diagnostic :severity)))
             (plist-get diagnostic :code)
             (plist-get diagnostic :message)))
   diagnostics "\n"))

(defun my/lifeos--diagnostic-guidance (diagnostic)
  "Return explanation and action strings for DIAGNOSTIC."
  (or (alist-get (plist-get diagnostic :code)
                 my/lifeos-diagnostic-remediations)
      '("This finding affects LifeOS planning."
        "Review the heading metadata and planning constraints.")))

(defun my/lifeos--format-task-explanation (title diagnostics)
  "Return a detailed explanation for TITLE and DIAGNOSTICS."
  (if (null diagnostics)
      (format "%s\n\nNo current LifeOS findings.\n" title)
    (concat
     title "\n\n"
     (mapconcat
      (lambda (severity)
        (let ((items (my/lifeos--diagnostics-with-severity diagnostics severity)))
          (when items
            (concat
             (upcase (symbol-name severity)) "\n\n"
             (mapconcat
              (lambda (diagnostic)
                (pcase-let ((`(,explanation ,action)
                             (my/lifeos--diagnostic-guidance diagnostic)))
                  (format "%s\n  %s\n  Why: %s\n  Fix: %s%s"
                          (plist-get diagnostic :code)
                          (plist-get diagnostic :message)
                          explanation action
                          (if-let* ((data (plist-get diagnostic :data)))
                              (format "\n  Affected: %s"
                                      (if (listp data)
                                          (string-join data ", ")
                                        data))
                            ""))))
               items "\n\n")))))
      my/lifeos-diagnostic-severity-order "\n\n"))))

(defun my/lifeos--enum-diagnostic (property values code)
  "Return a CODE diagnostic when PROPERTY is not one of VALUES."
  (let ((value (org-entry-get nil property)))
    (unless (member value values)
      (my/lifeos--diagnostic
       code 'error
       (format "%s must be one of: %s" property (string-join values ", "))))))

(defun my/lifeos--todo-descendant-headings ()
  "Return titles of descendant headings that have an Org TODO keyword."
  (save-excursion
    (org-back-to-heading t)
    (let ((end (save-excursion (org-end-of-subtree t t) (point)))
          descendants)
      (forward-line 1)
      (while (re-search-forward org-outline-regexp-bol end t)
        (goto-char (match-beginning 0))
        (when (org-get-todo-state)
          (push (org-get-heading t t t t) descendants))
        (forward-line 1))
      (nreverse descendants))))

(defun my/lifeos-executable-leaf-p ()
  "Return non-nil when the current heading is a leaf #task."
  (and (my/lifeos--heading-has-supertag-p "task")
       (null (my/lifeos--todo-descendant-headings))))

(defun my/lifeos-task-diagnostics ()
  "Return structured diagnostics for the active task heading at point.

DONE and CANCELLED headings have no active-task requirements."
  (save-excursion
    (org-back-to-heading t)
    (let* ((state (org-get-todo-state))
           (descendants (my/lifeos--todo-descendant-headings))
           (non-leaf-diagnostic
            (when (and descendants
                       (my/lifeos--heading-has-supertag-p "task"))
              (my/lifeos--diagnostic
               'non-leaf-task 'error
               (format "Executable task has TODO descendants: %s"
                       (string-join descendants ", "))
               descendants))))
      (cond
       ((member state '("DONE" "CANCELLED"))
        (delq nil (list non-leaf-diagnostic)))
       ((not (member state '("TODO" "NEXT" "WAITING" "SOMEDAY")))
        (list (my/lifeos--diagnostic
               'not-active-state 'error "Heading is not an active task state")))
       (t
        (let* ((id (org-entry-get nil "ID"))
               (priority (org-entry-get nil "PRIORITY"))
               (effort (org-entry-get nil "EFFORT"))
               (original-effort (org-entry-get nil "ORIGINAL_EFFORT"))
                (common
                 (list
                 (unless (my/lifeos--heading-has-supertag-p "task")
                   (my/lifeos--diagnostic
                    'missing-task-tag 'error "Missing #task"))
                 (unless (and id (not (string-empty-p id)))
                   (my/lifeos--diagnostic 'missing-id 'error "Missing ID"))
                  (my/lifeos--enum-diagnostic
                   "IMPACT" my/lifeos-impact-values 'invalid-impact)
                  (when (and (not (equal state "SOMEDAY"))
                             (org-entry-get nil "SCHEDULED")
                             (not (my/lifeos--timed-scheduled-time-at-point)))
                    (my/lifeos--diagnostic
                     'invalid-fixed-schedule 'error
                     "SCHEDULED fixed start must include HH:MM"))
                  non-leaf-diagnostic))
               (dependency-diagnostics
                (delq nil
                      (mapcar
                       (lambda (target)
                         (unless (org-id-find target)
                           (my/lifeos--diagnostic
                            'missing-dependency-target 'error
                            (format "Missing depends-on target: %s" target)
                            target)))
                       (my/lifeos--dependency-targets)))))
          (delq
           nil
           (append
            common
            dependency-diagnostics
            (pcase state
              ("SOMEDAY" nil)
              ("WAITING"
               (list
                (unless (member priority my/lifeos-priority-values)
                  (my/lifeos--diagnostic
                   'invalid-priority 'error "Priority must be A, B, C, or D"))
                (my/lifeos--enum-diagnostic
                 "WORK_MODE" my/lifeos-work-mode-values 'invalid-work-mode)
                (unless (my/lifeos--valid-effort-p effort)
                  (my/lifeos--diagnostic
                   'invalid-effort 'error "EFFORT must use H:MM"))
                (unless (my/lifeos--valid-effort-p original-effort)
                  (my/lifeos--diagnostic
                   'invalid-original-effort 'error
                   "ORIGINAL_EFFORT must use H:MM"))
                (when (and (my/lifeos--valid-effort-p effort)
                           (<= (my/lifeos-task-estimate-balance) 0))
                  (my/lifeos--diagnostic
                   'estimate-exhausted 'review
                   "Estimate is exhausted; re-estimate remaining work"))
                (unless (my/lifeos--waiting-reason-p)
                  (my/lifeos--diagnostic
                   'missing-waiting-reason 'error
                   "WAITING requires depends-on, WAIT_UNTIL, or WAITING_FOR"))))
              (_
               (list
                (unless (member priority my/lifeos-priority-values)
                  (my/lifeos--diagnostic
                   'invalid-priority 'error "Priority must be A, B, C, or D"))
                (unless (my/lifeos--valid-effort-p effort)
                  (my/lifeos--diagnostic
                   'invalid-effort 'error "EFFORT must use H:MM"))
                (unless (my/lifeos--valid-effort-p original-effort)
                  (my/lifeos--diagnostic
                   'invalid-original-effort 'error
                   "ORIGINAL_EFFORT must use H:MM"))
                (when (and (my/lifeos--valid-effort-p effort)
                           (<= (my/lifeos-task-estimate-balance) 0))
                  (my/lifeos--diagnostic
                   'estimate-exhausted 'review
                   "Estimate is exhausted; re-estimate remaining work"))
                (my/lifeos--enum-diagnostic
                 "WORK_MODE" my/lifeos-work-mode-values
                 'invalid-work-mode))))))))))))

(defun my/lifeos-task-validation-errors ()
  "Return metadata errors for the active task heading at point.

DONE and CANCELLED headings have no active-task requirements."
  (mapcar (lambda (diagnostic) (plist-get diagnostic :message))
          (my/lifeos-task-diagnostics)))

(defun my/lifeos-task-eligible-p (&optional states)
  "Return non-nil when the current task is valid and in one of STATES."
  (and (my/lifeos-executable-leaf-p)
       (member (org-get-todo-state)
               (or states '("TODO" "NEXT" "WAITING")))
       (not (seq-find (lambda (diagnostic)
                        (eq (plist-get diagnostic :severity) 'error))
                      (my/lifeos-task-diagnostics)))))

(defun my/lifeos-validate-task ()
  "Validate the task at point and report its metadata errors."
  (interactive)
  (let ((errors (my/lifeos-task-validation-errors)))
    (if errors
        (message "Needs grooming: %s" (string-join errors "; "))
      (message "Task metadata is valid"))
    errors))

(defun my/lifeos--read-property (property values &optional default)
  "Read PROPERTY from VALUES, using DEFAULT as the initial selection."
  (completing-read (format "%s: " property) values nil t nil nil default))

(defun my/lifeos-scaffold-task ()
  "Mark the heading at point as a task without starting the grooming wizard.

Create an ID and empty planning properties when they are absent. Existing
values are preserved so this command is safe for incomplete captured work."
  (interactive)
  (org-back-to-heading t)
  (when-let* ((descendants (my/lifeos--todo-descendant-headings)))
    (user-error "Cannot mark aggregate heading as #task; TODO descendants: %s"
                (string-join descendants ", ")))
  (my/lifeos--add-heading-supertag "task")
  (let ((id (org-id-get-create)))
    (dolist (property '("EFFORT" "ORIGINAL_EFFORT" "IMPACT" "WORK_MODE"))
      (unless (org-entry-get nil property)
        (org-entry-put nil property "")))
    (when (called-interactively-p 'interactive)
      (message "Task scaffolded: %s" id))
     id))

(defun my/lifeos-scaffold-project ()
  "Mark the heading at point as a project and add empty planning fields.

Create an ID and preserve every existing value.  This command records an
explicit user classification; LifeOS never infers projects from hierarchy."
  (interactive)
  (org-back-to-heading t)
  (when (my/lifeos--heading-has-supertag-p "task")
    (user-error "A #task heading cannot also be a #project"))
  (my/lifeos--add-heading-supertag "project")
  (let ((id (org-id-get-create)))
    (dolist (property '("PROJECT_EFFORT" "DEFAULT_WORK_MODE"
                        "PLANNING_CHUNK" "ESTIMATE_CONFIDENCE"))
      (unless (org-entry-get nil property)
        (org-entry-put nil property "")))
    (when (called-interactively-p 'interactive)
      (message "Project scaffolded: %s" id))
    id))

(defvar-local my/lifeos-diagnostic-overlays nil
  "Transient LifeOS diagnostic indicators in the current Org buffer.")

(defvar-local my/lifeos-diagnostics-dirty nil
  "Non-nil when the current buffer needs diagnostic refresh.")

(defvar-local my/lifeos-auto-scaffold-in-progress nil
  "Non-nil while automatic task scaffolding is changing the buffer.")

(defun my/lifeos--task-needs-scaffold-p ()
  "Return non-nil when the current #task heading lacks scaffold metadata."
  (and (my/lifeos--heading-has-supertag-p "task")
       (null (my/lifeos--todo-descendant-headings))
       (or (not (org-entry-get nil "ID"))
           (seq-some (lambda (property)
                       (not (org-entry-get nil property nil)))
                       '("EFFORT" "ORIGINAL_EFFORT" "IMPACT" "WORK_MODE")))))

(defun my/lifeos--project-needs-scaffold-p ()
  "Return non-nil when the current #project lacks scaffold metadata."
  (and (my/lifeos--heading-has-supertag-p "project")
       (not (my/lifeos--heading-has-supertag-p "task"))
       (or (not (org-entry-get nil "ID"))
           (seq-some (lambda (property)
                       (not (org-entry-get nil property nil)))
                     '("PROJECT_EFFORT" "DEFAULT_WORK_MODE"
                       "PLANNING_CHUNK" "ESTIMATE_CONFIDENCE")))))

(defun my/lifeos--auto-scaffold-heading-at-point ()
  "Scaffold the LifeOS heading at point when it needs metadata."
  (when (and (not my/lifeos-auto-scaffold-in-progress)
             (derived-mode-p 'org-mode)
             (org-at-heading-p))
    (let ((my/lifeos-auto-scaffold-in-progress t))
      (cond ((and my/lifeos-auto-scaffold-projects
                  (my/lifeos--project-needs-scaffold-p))
             (my/lifeos-scaffold-project))
            ((and my/lifeos-auto-scaffold-tasks
                  (my/lifeos--task-needs-scaffold-p))
             (my/lifeos-scaffold-task))))))

(defun my/lifeos-auto-scaffold-buffer ()
  "Scaffold every explicit #project and eligible #task in this Org buffer."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "LifeOS task scaffolding requires an Org buffer"))
  (unless my/lifeos-auto-scaffold-in-progress
    (let ((my/lifeos-auto-scaffold-in-progress t))
      (org-with-wide-buffer
       (org-map-entries
        (lambda ()
          (cond ((and my/lifeos-auto-scaffold-projects
                      (my/lifeos--project-needs-scaffold-p))
                 (my/lifeos-scaffold-project))
                ((and my/lifeos-auto-scaffold-tasks
                      (my/lifeos--task-needs-scaffold-p))
                 (my/lifeos-scaffold-task))))
         nil 'file)))))

(defun my/lifeos--clear-diagnostic-overlays ()
  "Remove transient LifeOS diagnostic indicators from the current buffer."
  (mapc #'delete-overlay my/lifeos-diagnostic-overlays)
  (setq my/lifeos-diagnostic-overlays nil))

(defun my/lifeos--make-diagnostic-overlay (label help &optional diagnostics kind)
  "Create a transient LABEL overlay with HELP at the current heading."
  (let ((overlay (make-overlay (line-beginning-position)
                               (line-beginning-position))))
    (overlay-put overlay 'before-string label)
    (overlay-put overlay 'help-echo help)
    (overlay-put overlay 'lifeos-diagnostics diagnostics)
    (overlay-put overlay 'lifeos-kind kind)
    (overlay-put overlay 'priority 100)
    (push overlay my/lifeos-diagnostic-overlays)
    overlay))

(defun my/lifeos--task-diagnostics-at-point ()
  "Return structural and cached forecast diagnostics for the task at point."
  (let ((diagnostics (my/lifeos-task-diagnostics)))
    (when-let* ((id (org-entry-get nil "ID"))
                (forecast-diagnostics
                 (and my/lifeos-project-analysis-cache
                      (gethash id
                               (plist-get my/lifeos-project-analysis-cache
                                          :task-diagnostics)))))
      (setq diagnostics (append diagnostics forecast-diagnostics)))
    diagnostics))

(defun my/lifeos-refresh-buffer-diagnostics ()
  "Refresh transient grooming indicators for the current Org buffer."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "LifeOS diagnostics require an Org buffer"))
  (my/lifeos--clear-diagnostic-overlays)
  (org-with-wide-buffer
   (org-map-entries
    (lambda ()
      (cond
       ((my/lifeos--heading-has-supertag-p "project")
         (let* ((project (my/lifeos-project-record-at-point))
                (diagnostics (plist-get project :diagnostics))
                (summary (my/lifeos--cached-project-summary-at-point)))
           (when (or diagnostics summary)
           (my/lifeos--make-diagnostic-overlay
             (concat (if diagnostics
                         (my/lifeos--diagnostic-label-string diagnostics) "")
                     (if summary
                         (my/lifeos--project-summary-label-string summary) ""))
             (string-join
              (delq nil
                    (list (and diagnostics
                               (my/lifeos--diagnostic-help diagnostics))
                          (and summary
                               (my/lifeos--format-project-explanation summary))))
              "\n\n")
             diagnostics 'project))))
        ((org-get-todo-state)
         (let ((diagnostics (my/lifeos--task-diagnostics-at-point)))
           (when diagnostics
             (my/lifeos--make-diagnostic-overlay
             (my/lifeos--diagnostic-label-string diagnostics)
             (my/lifeos--diagnostic-help diagnostics)
              diagnostics 'task))))))
    nil 'file))
  (setq my/lifeos-diagnostics-dirty nil)
  my/lifeos-diagnostic-overlays)

(defun my/lifeos--diagnostics-after-change (&rest _)
  "Mark the current buffer's LifeOS diagnostics stale after a change."
  (setq my/lifeos-diagnostics-dirty t)
  (my/lifeos-invalidate-project-analysis))

(defun my/lifeos--diagnostics-post-command ()
  "Refresh LifeOS diagnostics after the current command when needed."
  (when (and my/lifeos-diagnostics-dirty
             (derived-mode-p 'org-mode))
    (save-excursion
      (when (ignore-errors (org-back-to-heading t) t)
        (my/lifeos--auto-scaffold-heading-at-point)))
    (my/lifeos-refresh-buffer-diagnostics)))

(defun my/lifeos--maybe-enable-diagnostics ()
  "Enable LifeOS diagnostics for Org files under `org-directory'."
  (when (and buffer-file-name
             (file-directory-p org-directory)
             (file-in-directory-p (file-truename buffer-file-name)
                                  (file-truename org-directory)))
    (my/lifeos-diagnostics-mode 1)))

(define-minor-mode my/lifeos-diagnostics-mode
  "Show transient LifeOS grooming diagnostics in an Org buffer."
  :lighter " LifeDiag"
  (if my/lifeos-diagnostics-mode
      (progn
        (add-hook 'after-change-functions
                  #'my/lifeos--diagnostics-after-change nil t)
        (add-hook 'post-command-hook
                  #'my/lifeos--diagnostics-post-command nil t)
        (add-hook 'before-save-hook
                   #'my/lifeos-auto-scaffold-buffer nil t)
        (my/lifeos-refresh-buffer-diagnostics)
        (my/lifeos-invalidate-project-analysis))
    (remove-hook 'after-change-functions
                 #'my/lifeos--diagnostics-after-change t)
    (remove-hook 'post-command-hook
                 #'my/lifeos--diagnostics-post-command t)
    (remove-hook 'before-save-hook
                 #'my/lifeos-auto-scaffold-buffer t)
    (my/lifeos--clear-diagnostic-overlays)))

(add-hook 'org-mode-hook #'my/lifeos--maybe-enable-diagnostics)

(defun my/lifeos--diagnostic-overlay-positions ()
  "Return ascending positions of LifeOS diagnostic indicators."
  (sort (delq nil
              (mapcar (lambda (overlay)
                        (and (overlay-get overlay 'lifeos-diagnostics)
                             (overlay-start overlay)))
                      my/lifeos-diagnostic-overlays))
        #'<))

(defun my/lifeos--goto-diagnostic (forward-p)
  "Move point to the next heading with LifeOS diagnostics; wrap around.
Move forward when FORWARD-P, otherwise backward."
  (let ((positions (my/lifeos--diagnostic-overlay-positions)))
    (unless positions
      (user-error "No LifeOS diagnostics in this buffer"))
    (let* ((origin (point))
           (target (or (seq-find (if forward-p
                                     (lambda (pos) (> pos origin))
                                   (lambda (pos) (< pos origin)))
                                 (if forward-p positions (reverse positions)))
                       (if forward-p
                           (car positions)
                         (car (last positions))))))
      (widen)
      (goto-char target)
      (org-show-context)
      target)))

(defun my/lifeos-next-diagnostic ()
  "Move point to the next heading with a LifeOS grooming diagnostic."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "LifeOS diagnostics require an Org buffer"))
  (my/lifeos--goto-diagnostic t))

(defun my/lifeos-previous-diagnostic ()
  "Move point to the previous heading with a LifeOS grooming diagnostic."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "LifeOS diagnostics require an Org buffer"))
  (my/lifeos--goto-diagnostic nil))

(defun my/lifeos--effort-minutes (effort)
  "Convert an H:MM EFFORT string to integer minutes."
  (when (my/lifeos--valid-effort-p effort)
    (pcase-let ((`(,hours ,minutes) (mapcar #'string-to-number
                                           (split-string effort ":"))))
      (+ (* hours 60) minutes))))

(defun my/lifeos--direct-clocked-minutes ()
  "Return clocked minutes from the current heading, excluding descendants."
  (save-excursion
    (org-back-to-heading t)
    (let ((start (point))
          (bounds (my/lifeos--entry-section-bounds)))
      (if bounds
          (save-restriction
            (narrow-to-region start (cdr bounds))
            (org-clock-sum)
            org-clock-file-total-minutes)
        0))))

(defun my/lifeos-task-estimate-balance ()
  "Return EFFORT minus direct clocked minutes for the task at point."
  (when-let* ((effort (my/lifeos--effort-minutes
                       (org-entry-get nil "EFFORT"))))
    (- effort (my/lifeos--direct-clocked-minutes))))

(defun my/lifeos-task-forecast-minutes ()
  "Return positive forecast minutes for the task at point, or nil."
  (when-let* ((balance (my/lifeos-task-estimate-balance))
              ((> balance 0)))
    balance))

(defun my/lifeos--timed-scheduled-time-at-point ()
  "Return the current heading's committed start when it includes a time."
  (when-let* ((scheduled (org-entry-get nil "SCHEDULED"))
              ((string-match-p "[[:space:]][0-9][0-9]:[0-9][0-9]" scheduled)))
    (org-get-scheduled-time nil)))

;;; Correction-anchored effort
;;
;; EFFORT is the legacy display baseline.  Durable correction anchors live in
;; an append-only LIFEOS_EFFORT drawer on the task:
;;
;;   EPISODE id=<episode> task=<task-id> start=<UTC instant>
;;   CORRECTION id=<id> task=<task-id> episode=<episode> \
;;              effective=<UTC instant> remaining=<minutes> \
;;              revision=<stable revision>
;;
;; The drawer is never rewritten; a correction is appended.  EPISODE records
;; bind clocks to the effort episode in which they started.  A rewritten EFFORT
;; without a CORRECTION record stays legacy/unanchored, never an implicit
;; anchor.  Both record kinds carry the task ID so copying a drawer to another
;; task is detected instead of silently rebinding the correction.

(defconst my/lifeos--effort-drawer "LIFEOS_EFFORT"
  "Org drawer holding append-only effort episodes and corrections.")

(defconst my/lifeos--effort-instant-regexp
  (concat "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}"
          "T[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}"
          "\\(?:Z\\|[+-][0-9]\\{2\\}:[0-9]\\{2\\}\\)\\'")
  "Regexp matching a timezone-qualified ISO timestamp.")

(defun my/lifeos--effort-issue (code detail)
  "Return a structured effort-record issue."
  (list :code code :detail detail))

(defun my/lifeos--effort-instant-minutes (instant)
  "Return epoch minutes for minute-aligned INSTANT, or nil."
  (when (and (stringp instant)
             (string-match-p my/lifeos--effort-instant-regexp instant))
    (condition-case nil
        (let ((seconds (float-time (date-to-time instant))))
          (and (zerop (% (truncate seconds) 60))
               (/ (truncate seconds) 60)))
      (error nil))))

(defun my/lifeos--effort-effective-instant (&optional instant)
  "Return INSTANT or the current UTC minute, validated and minute aligned."
  (let ((value (or instant
                   (format-time-string "%Y-%m-%dT%H:%M:00Z" nil t))))
    (unless (my/lifeos--effort-instant-minutes value)
      (user-error "Correction instant must be a minute-aligned ISO timestamp"))
    value))

(defun my/lifeos--effort-task-id ()
  "Return the current heading's stable task ID, or nil."
  (let ((id (org-entry-get nil "ID")))
    (and id (not (string-empty-p id)) id)))

(defun my/lifeos--effort-property (name)
  "Return non-empty property NAME for the current heading, or nil."
  (let ((value (org-entry-get nil name)))
    (and value (not (string-empty-p (string-trim value))) value)))

(defun my/lifeos--effort-drawer-regions ()
  "Return (:content-start :content-end :closed-p) for effort drawers."
  (save-excursion
    (when-let* ((section (my/lifeos--entry-section-bounds)))
      (goto-char (car section))
      (let (regions)
        (while (re-search-forward
                (format "^[ \t]*:%s:[ \t]*$" my/lifeos--effort-drawer)
                (cdr section) t)
          (let ((content-start (progn (forward-line 1) (point))))
            (if (re-search-forward "^[ \t]*:END:[ \t]*$" (cdr section) t)
                (push (list :content-start content-start
                            :content-end (match-beginning 0)
                            :closed-p t)
                      regions)
              ;; An unclosed drawer is a record-integrity error, not an empty
              ;; drawer.  Stop at the section end; nothing after it belongs to
              ;; the effort record.
              (push (list :content-start content-start
                          :content-end (cdr section)
                          :closed-p nil)
                    regions)
              (goto-char (cdr section)))))
        (nreverse regions)))))

(defun my/lifeos--effort-record-lines ()
  "Return non-empty record lines from the current task's effort drawers."
  (let (lines)
    (dolist (region (my/lifeos--effort-drawer-regions))
      (save-excursion
        (goto-char (plist-get region :content-start))
        (while (< (point) (plist-get region :content-end))
          (let ((line (string-trim
                       (buffer-substring-no-properties
                        (line-beginning-position) (line-end-position)))))
            (unless (string-empty-p line)
              (push line lines)))
          (forward-line 1))))
    (nreverse lines)))

(defun my/lifeos--direct-clock-records ()
  "Return raw direct CLOCK records for the current heading."
  (save-excursion
    (org-back-to-heading t)
    (when-let* ((bounds (my/lifeos--entry-section-bounds)))
      (save-restriction
        (narrow-to-region (car bounds) (cdr bounds))
        (goto-char (point-min))
        (let (records)
          (while (re-search-forward
                  "^[ \t]*CLOCK:[ \t]*\\[\\([^]]+\\)\\]\\(?:--\\[\\([^]]+\\)\\]\\)?"
                  nil t)
            (push (list :start (match-string-no-properties 1)
                        :end (match-string-no-properties 2))
                  records))
          (nreverse records))))))

(defun my/lifeos--clock-utc (text)
  "Return (EPOCH . UTC-STRING) for an Org clock timestamp TEXT, or nil.
Org clock lines are local wall time; this conversion uses the machine zone.
A trusted scheduler adapter must carry explicit zone evidence instead."
  (condition-case nil
      (let* ((time (org-time-string-to-time text))
             (seconds (float-time time)))
        (and (zerop (% (truncate seconds) 60))
             (cons (truncate seconds)
                   (format-time-string "%Y-%m-%dT%H:%M:%SZ" time t))))
    (error nil)))

(defun my/lifeos--effort-correction-summary
    (task-id episode-id effective remaining)
  "Return the stable payload summary for one correction."
  (secure-hash 'sha256
               (format "%s|%s|%s|%d"
                       task-id episode-id effective remaining)))

(defun my/lifeos--effort-correction-id
    (task-id episode-id effective remaining)
  "Return the deterministic correction ID for a correction payload."
  (concat "c-" (substring
                (my/lifeos--effort-correction-summary
                 task-id episode-id effective remaining)
                0 16)))

(defun my/lifeos--effort-correction-revision
    (task-id episode-id effective remaining)
  "Return the stable revision for a correction payload."
  (substring (my/lifeos--effort-correction-summary
              task-id episode-id effective remaining)
             0 16))

(defun my/lifeos--effort-episode-id (task-id start)
  "Return the deterministic effort episode ID for TASK-ID and START."
  (concat "e-" (substring (secure-hash 'sha256
                                        (format "%s|%s" task-id start))
                           0 16)))

(defun my/lifeos-effort-state ()
  "Return the persisted effort state for the task at point.

The state separates legacy EFFORT from durable correction anchors.  Clocks are
attributed to the effort episode in which they started; an unattributable or
episode-crossing clock is an issue, never a silent guess.  Clock instants use
the machine zone (`:clock-zone-basis' is `machine-local'), so this state is not
trusted coverage evidence.  `:valid-p' covers record integrity only; missing or
legacy effort is reported through `:effort-provenance'."
  (save-excursion
    (org-back-to-heading t)
    (let* ((task-id (my/lifeos--effort-task-id))
           (lines (my/lifeos--effort-record-lines))
           (regions (my/lifeos--effort-drawer-regions))
           (issues nil)
           (episodes nil)
           (corrections nil)
           (seen-corrections (make-hash-table :test #'equal))
           (effort-text (my/lifeos--effort-property "EFFORT"))
           (original-text (my/lifeos--effort-property "ORIGINAL_EFFORT"))
           (effort-minutes (my/lifeos--effort-minutes effort-text))
           (original-minutes (my/lifeos--effort-minutes original-text)))
      (when (cdr regions)
        (push (my/lifeos--effort-issue
               'duplicate-effort-drawer
               (format "task has %d %s drawers"
                       (length regions) my/lifeos--effort-drawer))
              issues))
      (dolist (region regions)
        (unless (plist-get region :closed-p)
          (push (my/lifeos--effort-issue
                 'unclosed-effort-drawer
                 (format "%s drawer has no :END:" my/lifeos--effort-drawer))
                issues)))
      (when (and (null task-id) (or lines effort-text))
        (push (my/lifeos--effort-issue
               'missing-task-id
               "effort records require the task's stable ID")
              issues))
      (when (and effort-text (null effort-minutes))
        (push (my/lifeos--effort-issue
               'malformed-effort
               (format "EFFORT %S is not an H:MM duration" effort-text))
              issues))
      (when (and effort-minutes (zerop effort-minutes))
        ;; The scheduling snapshot requires a positive initial baseline; a zero
        ;; EFFORT is exhausted/unknown, not a zero-duration demand.
        (push (my/lifeos--effort-issue
               'nonpositive-effort
               "EFFORT must be positive; zero means exhausted, not demand")
              issues))
      (dolist (line lines)
        (cond
         ((string-match
           (concat "\\`EPISODE id=\\([^ \t]+\\)"
                   " task=\\([^ \t]+\\)"
                   " start=\\([^ \t]+\\)\\'")
           line)
          (let ((id (match-string 1 line))
                (record-task (match-string 2 line))
                (start (match-string 3 line)))
            (when (and task-id (not (equal record-task task-id)))
              (push (my/lifeos--effort-issue
                     'episode-task-mismatch
                     (format "episode %s is bound to task %s, not %s"
                             id record-task task-id))
                    issues))
            (if (null (my/lifeos--effort-instant-minutes start))
                (push (my/lifeos--effort-issue
                       'malformed-episode
                       (format "episode %s has invalid start %s" id start))
                      issues)
              (let ((existing (seq-find
                               (lambda (episode)
                                 (equal (plist-get episode :id) id))
                               episodes)))
                (cond
                 ((null existing)
                  (push (list :id id :task-id record-task :start start)
                        episodes))
                 ((not (equal (plist-get existing :start) start))
                  (push (my/lifeos--effort-issue
                         'duplicate-episode-id
                         (format "episode %s has conflicting starts" id))
                        issues)))))))
         ((string-match
           (concat "\\`CORRECTION id=\\([^ \t]+\\)"
                   " task=\\([^ \t]+\\)"
                   " episode=\\([^ \t]+\\)"
                   " effective=\\([^ \t]+\\)"
                   " remaining=\\([0-9]+\\)"
                   " revision=\\([^ \t]+\\)\\'")
           line)
          (let ((id (match-string 1 line))
                (record-task (match-string 2 line))
                (episode-id (match-string 3 line))
                (effective (match-string 4 line))
                (remaining (string-to-number (match-string 5 line)))
                (revision (match-string 6 line)))
            (when (and task-id (not (equal record-task task-id)))
              (push (my/lifeos--effort-issue
                     'correction-task-mismatch
                     (format "correction %s is bound to task %s, not %s"
                             id record-task task-id))
                    issues))
            (if (null (my/lifeos--effort-instant-minutes effective))
                (push (my/lifeos--effort-issue
                       'malformed-correction
                       (format "correction %s has invalid effective instant %s"
                               id effective))
                      issues)
              (let ((record (list :correction-id id
                                  :task-id record-task
                                  :episode-id episode-id
                                  :effective-at effective
                                  :remaining-minutes remaining
                                  :revision revision)))
                (let ((previous (gethash id seen-corrections)))
                  (cond
                   ((null previous)
                    (puthash id record seen-corrections)
                    (push record corrections))
                   ((not (equal previous record))
                    (push (my/lifeos--effort-issue
                           'duplicate-correction-id
                           (format "correction %s has conflicting payloads" id))
                          issues))))
                (unless (equal
                         revision
                         (my/lifeos--effort-correction-revision
                          record-task episode-id effective remaining))
                  (push (my/lifeos--effort-issue
                         'correction-revision-mismatch
                         (format "correction %s revision does not match its payload"
                                 id))
                        issues))))))
         (t
          (push (my/lifeos--effort-issue
                 'unknown-effort-record
                 (format "unknown effort record: %s" line))
                issues))))
      (setq episodes
            (sort episodes
                  (lambda (left right)
                    (< (my/lifeos--effort-instant-minutes
                        (plist-get left :start))
                       (my/lifeos--effort-instant-minutes
                        (plist-get right :start))))))
      (let ((starts (make-hash-table :test #'equal)))
        (dolist (episode episodes)
          (let ((start (my/lifeos--effort-instant-minutes
                        (plist-get episode :start))))
            (when (gethash start starts)
              (push (my/lifeos--effort-issue
                     'conflicting-episode-start
                     (format "different episodes start at %s"
                             (plist-get episode :start)))
                    issues))
            (puthash start t starts))))
      (let ((episode-ids (mapcar (lambda (episode)
                                   (plist-get episode :id))
                                 episodes)))
        (dolist (correction corrections)
          (unless (member (plist-get correction :episode-id) episode-ids)
            (push (my/lifeos--effort-issue
                   'unknown-correction-episode
                   (format "correction %s references unknown episode %s"
                           (plist-get correction :correction-id)
                           (plist-get correction :episode-id)))
                  issues))))
      (let ((by-effective (make-hash-table :test #'equal)))
        (dolist (correction corrections)
          (let* ((effective (plist-get correction :effective-at))
                 (previous (gethash effective by-effective)))
            (if (null previous)
                (puthash effective correction by-effective)
              (unless (equal previous correction)
                (push (my/lifeos--effort-issue
                       'conflicting-correction-effective
                       (format "different corrections share effective instant %s"
                               effective))
                      issues))))))
      (setq corrections
            (sort corrections
                  (lambda (left right)
                    (string< (plist-get left :effective-at)
                             (plist-get right :effective-at)))))
      (let* ((latest (car (last episodes)))
             (episode-starts (mapcar
                              (lambda (episode)
                                (cons (* 60 (my/lifeos--effort-instant-minutes
                                             (plist-get episode :start)))
                                      episode))
                              episodes))
             (clocks nil))
        (dolist (raw (my/lifeos--direct-clock-records))
          (let* ((start-info (my/lifeos--clock-utc (plist-get raw :start)))
                 (end-info (and (plist-get raw :end)
                                (my/lifeos--clock-utc (plist-get raw :end)))))
            (cond
             ((null start-info)
              (push (my/lifeos--effort-issue
                     'malformed-clock
                     (format "clock start %S is not a minute-aligned Org timestamp"
                             (plist-get raw :start)))
                    issues))
             ((and (plist-get raw :end) (null end-info))
              (push (my/lifeos--effort-issue
                     'malformed-clock
                     (format "clock end %S is not a minute-aligned Org timestamp"
                             (plist-get raw :end)))
                    issues))
             ((and end-info (<= (car end-info) (car start-info)))
              (push (my/lifeos--effort-issue
                     'malformed-clock
                     "clock end must be after its start")
                    issues))
             (t
              (let* ((start-epoch (car start-info))
                     (episode (cdr (seq-find
                                    (lambda (entry)
                                      (<= (car entry) start-epoch))
                                    (reverse episode-starts))))
                     (next (seq-find
                            (lambda (entry)
                              (> (car entry) start-epoch))
                            episode-starts)))
                (cond
                 ((null episode)
                  (push (my/lifeos--effort-issue
                         'clock-before-episode
                         (format "clock at %s predates every effort episode"
                                 (cdr start-info)))
                        issues))
                 ((and next
                       (or (null end-info)
                           (> (car end-info) (car next))))
                  (push (my/lifeos--effort-issue
                         'clock-crosses-episode
                         (format "clock at %s crosses episode %s"
                                 (cdr start-info)
                                 (plist-get (cdr next) :id)))
                        issues))
                 (t
                  (push (list :clock-id nil
                              :task-id task-id
                              :episode-id (plist-get episode :id)
                              :started-at (cdr start-info)
                              :ended-at (and end-info (cdr end-info)))
                        clocks))))))))
        (setq clocks (nreverse clocks))
        (let ((current-corrections
               (seq-filter
                (lambda (correction)
                  (equal (plist-get correction :episode-id)
                         (plist-get latest :id)))
                corrections)))
          (list :task-id task-id
                :title (org-get-heading t t t t)
                :valid-p (null issues)
                :issues (nreverse issues)
                :episodes episodes
                :episode-id (plist-get latest :id)
                :episode-started-at (plist-get latest :start)
                :corrections corrections
                :current-episode-corrections current-corrections
                :clocks clocks
                :clock-zone-basis 'machine-local
                :effort-minutes effort-minutes
                :effort-provenance
                (cond
                 ((null effort-minutes) 'missing)
                 ;; Without a valid ORIGINAL_EFFORT, an explicit initial
                 ;; baseline cannot be distinguished from a rewrite.
                 ((null original-minutes) 'legacy-rewritten)
                 ((/= original-minutes effort-minutes) 'legacy-rewritten)
                 (t 'explicit-initial))
                :correction-anchored-p
                (and current-corrections t)))))))

(defun my/lifeos--effort-append-record (record)
  "Append RECORD to the current task's LIFEOS_EFFORT drawer."
  (save-excursion
    (org-back-to-heading t)
    (let ((regions (my/lifeos--effort-drawer-regions)))
      (cond
       ((cdr regions)
        (user-error "Multiple %s drawers; resolve them before adding a correction"
                    my/lifeos--effort-drawer))
       ((and regions (not (plist-get (car regions) :closed-p)))
        (user-error "The %s drawer is unclosed; add :END: before recording"
                    my/lifeos--effort-drawer))
       (regions
        (goto-char (plist-get (car regions) :content-end))
        (insert record "\n"))
       (t
        (org-end-of-meta-data)
        (insert (format ":%s:\n%s\n:END:\n"
                        my/lifeos--effort-drawer record)))))))

(defun my/lifeos--effort-earliest-clock-start ()
  "Return the earliest direct clock start as a UTC instant, or nil."
  (let (earliest)
    (dolist (raw (my/lifeos--direct-clock-records))
      (let ((info (my/lifeos--clock-utc (plist-get raw :start))))
        (unless info
          (user-error "Cannot anchor effort while a clock line is malformed"))
        (when (or (null earliest) (< (car info) earliest))
          (setq earliest (car info)))))
    (and earliest
         (format-time-string "%Y-%m-%dT%H:%M:%SZ"
                             (seconds-to-time earliest) t))))

(defun my/lifeos--effort-resolve-episode (state effective)
  "Return (ID START NEW-P) for STATE, beginning at the earliest clock."
  (let ((existing-id (plist-get state :episode-id)))
    (if existing-id
        (progn
          (unless (plist-get state :valid-p)
            (user-error "Resolve effort-record issues before adding a correction"))
          (let ((start (plist-get state :episode-started-at)))
            (when (< (my/lifeos--effort-instant-minutes effective)
                     (my/lifeos--effort-instant-minutes start))
              (user-error "Correction instant precedes the effort episode start"))
            (list existing-id start nil)))
      (let ((allowed '(clock-before-episode)))
        (dolist (issue (plist-get state :issues))
          (unless (memq (plist-get issue :code) allowed)
            (user-error "Resolve effort-record issue %s before adding a correction"
                        (plist-get issue :code)))))
      (let ((task-id (plist-get state :task-id)))
        (unless task-id
          (user-error "Effort corrections require the task's stable ID"))
        (let* ((start (or (my/lifeos--effort-earliest-clock-start)
                          effective))
               (episode-id (my/lifeos--effort-episode-id task-id start)))
          (when (< (my/lifeos--effort-instant-minutes effective)
                   (my/lifeos--effort-instant-minutes start))
            (user-error "Correction instant precedes the effort episode start"))
          (list episode-id start t))))))

(defun my/lifeos-set-remaining-effort (minutes &optional effective)
  "Record remaining MINUTES as an append-only effort correction.

EFFECTIVE defaults to the current UTC minute and exists for deterministic
callers.  The legacy EFFORT value is still updated for display
(clocked + MINUTES), but the durable correction anchor is authoritative.  An
identical correction at the same instant is idempotent; a different one is
refused rather than creating a conflicting record."
  (interactive "nRemaining minutes: ")
  (unless (and (integerp minutes) (>= minutes 0))
    (user-error "Remaining minutes cannot be negative"))
  (org-back-to-heading t)
  (let* ((effective (my/lifeos--effort-effective-instant effective))
         (task-id (my/lifeos--effort-task-id)))
    (unless task-id
      (user-error "Effort corrections require the task's stable ID"))
    (let* ((state (my/lifeos-effort-state))
           (resolved (my/lifeos--effort-resolve-episode state effective))
           (episode-id (nth 0 resolved))
           (episode-start (nth 1 resolved))
           (new-episode-p (nth 2 resolved))
           (existing (seq-find
                      (lambda (correction)
                        (equal (plist-get correction :effective-at)
                               effective))
                      (plist-get state :corrections))))
      (when existing
        (unless (and (equal (plist-get existing :episode-id) episode-id)
                     (= (plist-get existing :remaining-minutes) minutes))
          (user-error
           "A different effort correction is already effective at %s"
           effective)))
      (let* ((current (org-entry-get nil "EFFORT"))
             (total (+ (my/lifeos--direct-clocked-minutes) minutes))
             (effort (format "%d:%02d" (/ total 60) (% total 60))))
        (atomic-change-group
          (when new-episode-p
            (my/lifeos--effort-append-record
             (format "EPISODE id=%s task=%s start=%s"
                     episode-id task-id episode-start)))
          (unless (my/lifeos--valid-effort-p
                   (org-entry-get nil "ORIGINAL_EFFORT"))
            (org-entry-put nil "ORIGINAL_EFFORT"
                           (if (my/lifeos--valid-effort-p current)
                               current effort)))
          (org-entry-put nil "EFFORT" effort)
          (unless existing
            (my/lifeos--effort-append-record
             (format (concat "CORRECTION id=%s task=%s episode=%s"
                             " effective=%s remaining=%d revision=%s")
                     (my/lifeos--effort-correction-id
                      task-id episode-id effective minutes)
                     task-id episode-id effective minutes
                     (my/lifeos--effort-correction-revision
                      task-id episode-id effective minutes)))))
        effort))))

(defun my/lifeos-groom-task ()
  "Interactively establish required metadata for the task at point."
  (interactive)
  (org-back-to-heading t)
  (let ((state (org-get-todo-state)))
    (unless (member state '("TODO" "NEXT" "WAITING" "SOMEDAY"))
      (user-error "Heading must be TODO, NEXT, WAITING, or SOMEDAY"))
    (when-let* ((descendants (my/lifeos--todo-descendant-headings)))
      (user-error "Cannot groom aggregate heading; TODO descendants: %s"
                  (string-join descendants ", ")))
    (my/lifeos--add-heading-supertag "task")
    (org-id-get-create)
    (let ((impact (my/lifeos--read-property
                     "IMPACT" my/lifeos-impact-values
                     (org-entry-get nil "IMPACT"))))
      (org-entry-put nil "IMPACT" impact))
    (unless (equal state "SOMEDAY")
      (let ((priority (my/lifeos--read-property
                       "PRIORITY" my/lifeos-priority-values
                       (org-entry-get nil "PRIORITY")))
            (work-mode (my/lifeos--read-property
                        "WORK_MODE" my/lifeos-work-mode-values
                        (org-entry-get nil "WORK_MODE"))))
        (org-priority (string-to-char priority))
        (org-entry-put nil "WORK_MODE" work-mode))
      (let* ((current (org-entry-get nil "EFFORT"))
             (effort (read-string "Expected total EFFORT (H:MM): " current)))
        (unless (my/lifeos--valid-effort-p effort)
          (user-error "EFFORT must use H:MM"))
        (unless (my/lifeos--valid-effort-p
                 (org-entry-get nil "ORIGINAL_EFFORT"))
          (org-entry-put nil "ORIGINAL_EFFORT" effort))
        (org-entry-put nil "EFFORT" effort))
      (when (and (equal state "WAITING")
                 (not (my/lifeos--waiting-reason-p)))
        (let ((waiting-for (read-string "WAITING_FOR: ")))
          (unless (string-empty-p waiting-for)
            (org-entry-put nil "WAITING_FOR" waiting-for)))))
    (my/lifeos-validate-task)))

(defun my/lifeos--read-project-duration (prompt current)
  "Read a positive 15-minute-aligned duration with PROMPT and CURRENT default."
  (let ((value (read-string (format "%s (H:MM): " prompt) current)))
    (unless (my/lifeos--aligned-positive-duration-minutes value)
      (user-error "%s must be positive and aligned to 15 minutes" prompt))
    value))

(defun my/lifeos-groom-project ()
  "Interactively establish required metadata for the project at point.

Prompts use plain-language labels; callers do not need to know Org property
names. Existing values are offered as defaults and remain editable."
  (interactive)
  (org-back-to-heading t)
  (let* ((current-deadline (org-entry-get nil "DEADLINE"))
         (default-date
          (and current-deadline
               (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}"
                             current-deadline)
               (match-string 0 current-deadline)))
         (id (my/lifeos-scaffold-project))
         (deadline (org-read-date nil nil nil "Project deadline: "
                                  nil default-date))
         (effort (my/lifeos--read-project-duration
                  "Total expected project effort"
                  (org-entry-get nil "PROJECT_EFFORT")))
         (work-mode (my/lifeos--read-property
                     "Usual work mode" my/lifeos-work-mode-values
                     (org-entry-get nil "DEFAULT_WORK_MODE")))
         (chunk (my/lifeos--read-project-duration
                 "Largest planning chunk"
                 (org-entry-get nil "PLANNING_CHUNK")))
          (confidence (my/lifeos--read-property
                       "Estimate confidence" my/lifeos-estimate-confidence-values
                       (org-entry-get nil "ESTIMATE_CONFIDENCE"))))
    (org-deadline nil deadline)
    (org-entry-put nil "PROJECT_EFFORT" effort)
    (org-entry-put nil "DEFAULT_WORK_MODE" work-mode)
    (org-entry-put nil "PLANNING_CHUNK" chunk)
    (org-entry-put nil "ESTIMATE_CONFIDENCE" confidence)
    (let* ((project (my/lifeos-project-record-at-point))
           (diagnostics (plist-get project :diagnostics)))
      (when (called-interactively-p 'interactive)
        (if diagnostics
            (message "Project still needs grooming: %s"
                     (mapconcat (lambda (diagnostic)
                                  (plist-get diagnostic :message))
                                diagnostics "; "))
          (message "Project metadata is valid"))))
    id))

(define-derived-mode my/lifeos-grooming-report-mode special-mode
  "LifeOS-Grooming"
  "Major mode for LifeOS Needs Grooming reports.")

(defun my/lifeos--grooming-record ()
  "Return a grooming record for the heading at point."
  (let* ((project-heading (my/lifeos--heading-has-supertag-p "project"))
         (project (if project-heading
                      (my/lifeos-project-record-at-point)
                    (my/lifeos--project-at-point)))
         (diagnostics (if project-heading
                          (plist-get project :diagnostics)
                        (my/lifeos-task-diagnostics))))
    (when diagnostics
      (list :kind (if project-heading 'project 'task)
            :marker (copy-marker (point))
            :title (org-get-heading t t t t)
            :todo (org-get-todo-state)
            :project-id (plist-get project :id)
            :project-key (plist-get project :key)
            :project-title (plist-get project :title)
            :diagnostics diagnostics
            :errors (mapcar (lambda (diagnostic)
                              (plist-get diagnostic :message))
                            diagnostics)))))

(defun my/lifeos--nearest-project-marker ()
  "Return a marker for the nearest #project heading at or above point."
  (save-excursion
    (org-back-to-heading t)
    (catch 'project
      (while t
        (when (my/lifeos--heading-has-supertag-p "project")
          (throw 'project (copy-marker (point))))
        (unless (org-up-heading-safe)
          (throw 'project nil))))))

(defun my/lifeos--grooming-records (scope)
  "Return typed invalid task and explicit project records selected by SCOPE."
  (require 'org-ql)
  (org-id-update-id-locations org-agenda-files)
  (let* ((active '(todo "TODO" "NEXT" "WAITING" "SOMEDAY"))
         (query
          (pcase scope
            ('all active)
            ('due-soon `(and ,active (deadline :to 14)))
            ('recent `(and ,active (ts :from -14 :to today)))
            ('project active)
            (_ (error "Unknown grooming scope: %s" scope)))))
    (let* ((project-marker (and (eq scope 'project)
                                (my/lifeos--nearest-project-marker)))
           (records
            (delq
             nil
             (if (eq scope 'project)
                 (progn
                   (unless project-marker
                     (user-error "Point is not inside a #project subtree"))
                   (with-current-buffer (marker-buffer project-marker)
                     (save-restriction
                       (widen)
                       (goto-char project-marker)
                       (org-narrow-to-subtree)
                       (org-ql-select (current-buffer) query
                         :action #'my/lifeos--grooming-record
                         :narrow t))))
               (org-ql-select org-agenda-files query
                 :action #'my/lifeos--grooming-record))))
           (seen (mapcar (lambda (record)
                           (cons (marker-buffer (plist-get record :marker))
                                 (marker-position (plist-get record :marker))))
                         records)))
      ;; Projects without TODO states are invisible to the active-state query.
      (when (memq scope '(all project))
        (dolist (file (if project-marker
                          (list (buffer-file-name (marker-buffer project-marker)))
                        (delete-dups (copy-sequence org-agenda-files))))
          (when (and file (file-readable-p file))
            (with-current-buffer (find-file-noselect file)
              (org-with-wide-buffer
               (org-map-entries
                (lambda ()
                  (when (and (my/lifeos--heading-has-supertag-p "project")
                             (or (not project-marker)
                                 (save-excursion
                                   (let ((candidate (point)))
                                     (goto-char project-marker)
                                     (let ((end (save-excursion
                                                  (org-end-of-subtree t t)
                                                  (point))))
                                       (<= (marker-position project-marker)
                                           candidate end)))))
                             (not (member (cons (current-buffer) (point)) seen)))
                    (when-let* ((record (my/lifeos--grooming-record)))
                      (push record records))))
                nil 'file)))))
      (nreverse records)))))

(defun my/lifeos--visit-grooming-marker (button)
  "Visit the Org heading stored on BUTTON."
  (let ((marker (button-get button 'org-marker)))
    (pop-to-buffer (marker-buffer marker))
    (goto-char marker)
    (org-show-context)))

(defun my/lifeos-needs-grooming (scope)
  "Show active headings that fail validation within SCOPE."
  (interactive
   (list
    (intern
     (completing-read
      "Grooming scope: "
      '("all" "due-soon" "project" "recent") nil t nil nil "all"))))
  (let ((records (my/lifeos--grooming-records scope))
        (buffer (get-buffer-create "*LifeOS Needs Grooming*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/lifeos-grooming-report-mode)
        (insert (format "Needs Grooming: %s (%d)\n\n" scope (length records)))
        (dolist (record records)
          (let* ((marker (plist-get record :marker))
                 (file (buffer-file-name (marker-buffer marker)))
                 (line (with-current-buffer (marker-buffer marker)
                         (line-number-at-pos marker))))
            (insert-text-button
             (plist-get record :title)
             'follow-link t
             'org-marker marker
             'action #'my/lifeos--visit-grooming-marker)
            (insert (format "  [%s%s]  %s:%d\n"
                            (upcase (symbol-name (plist-get record :kind)))
                            (if-let* ((todo (plist-get record :todo)))
                                (format " %s" todo) "")
                            (file-name-nondirectory file)
                            line))
            (dolist (error (plist-get record :errors))
              (insert (format "  - %s\n" error)))
            (insert "\n")))
        (goto-char (point-min))))
    (pop-to-buffer buffer)
    records))

(defun my/lifeos--dependency-graph ()
  "Return an alist mapping task IDs to their depends-on target IDs."
  (let (graph)
    (dolist (file (delete-dups (copy-sequence org-agenda-files)))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (org-map-entries
            (lambda ()
              (when (my/lifeos-executable-leaf-p)
                (when-let* ((id (org-entry-get nil "ID")))
                  (push (cons id (my/lifeos--dependency-targets)) graph))))
            nil 'file)))))
    graph))

(defun my/lifeos--dependency-path (from target graph &optional visited)
  "Return a path from FROM to TARGET in GRAPH, or nil."
  (cond
   ((equal from target) (list from))
   ((member from visited) nil)
   (t
    (seq-some
     (lambda (next)
       (when-let* ((path (my/lifeos--dependency-path
                          next target graph (cons from visited))))
         (cons from path)))
     (alist-get from graph nil nil #'equal)))))

(defun my/lifeos--task-id-eligible-p (id &optional states)
  "Return non-nil when ID identifies a valid executable task in STATES."
  (when-let* ((marker (org-id-find id 'marker)))
    (with-current-buffer (marker-buffer marker)
      (save-excursion
        (goto-char marker)
        (my/lifeos-task-eligible-p states)))))

(defun my/lifeos-dependency-cycles ()
  "Return dependency cycle paths found in active Org files."
  (interactive)
  (let ((graph (my/lifeos--dependency-graph)) cycles)
    (dolist (entry graph)
      (dolist (target (cdr entry))
        (when-let* ((path (my/lifeos--dependency-path
                           target (car entry) graph)))
          (push (cons (car entry) path) cycles))))
    (when (called-interactively-p 'interactive)
      (if cycles
          (message "Dependency cycles: %s"
                   (mapconcat (lambda (path) (string-join path " -> "))
                              cycles "; "))
        (message "Dependency graph is acyclic")))
    cycles))

(defun my/lifeos-add-dependency ()
  "Add a cycle-safe depends-on link from the current task to another task."
  (interactive)
  (require 'supertag)
  (org-back-to-heading t)
  (unless (my/lifeos--heading-has-supertag-p "task")
    (user-error "Current heading is not a #task"))
  (when-let* ((descendants (my/lifeos--todo-descendant-headings)))
    (user-error "Aggregate #task cannot have dependencies; TODO descendants: %s"
                (string-join descendants ", ")))
  (let* ((source-id (or (org-entry-get nil "ID") (org-id-get-create)))
         (task-ids
          (seq-filter
           (lambda (id)
             (and (not (equal id source-id))
                  (my/lifeos--task-id-eligible-p
                   id '("TODO" "NEXT" "WAITING" "SOMEDAY"))))
           (supertag-query-node-ids '(tag "task"))))
         (candidates
          (mapcar
           (lambda (id)
             (let ((title (plist-get (supertag-node-get id) :title)))
               (cons (format "%s  [%s]" title id) id)))
           task-ids))
         (selection (completing-read "Depends on task: " candidates nil t))
         (target-id (cdr (assoc selection candidates))))
    (unless target-id
      (user-error "No dependency target selected"))
    (let* ((target-title (plist-get (supertag-node-get target-id) :title))
           (graph (my/lifeos--dependency-graph))
           (cycle-path (my/lifeos--dependency-path target-id source-id graph)))
      (when cycle-path
        (user-error "Dependency would create cycle: %s"
                    (string-join (cons source-id cycle-path) " -> ")))
      (when (member target-id (my/lifeos--dependency-targets))
        (user-error "Task already depends on %s" target-title))
      (org-end-of-meta-data)
      (unless (bolp) (insert "\n"))
      (insert (format "Depends on [[depends-on:%s][%s]].\n"
                      target-id target-title))
      (save-buffer)
      (message "Added dependency on %s" target-title))))

(defun my/lifeos--insert-dependency (target-id target-title)
  "Insert a dependency on TARGET-ID named TARGET-TITLE at the current heading."
  (org-end-of-meta-data)
  (unless (bolp) (insert "\n"))
  (insert (format "Depends on [[depends-on:%s][%s]].\n"
                  target-id target-title)))

(defun my/lifeos--rewire-dependency-target (old-id new-id)
  "Replace depends-on links to OLD-ID with NEW-ID in agenda files.

Return the number of links changed. Buffers are modified but not saved."
  (let ((regexp (concat "depends-on:" (regexp-quote old-id)))
        (replacement (concat "depends-on:" new-id))
        (changed 0))
    (dolist (file (delete-dups (copy-sequence org-agenda-files)))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (goto-char (point-min))
           (while (re-search-forward regexp nil t)
             (replace-match replacement t t)
             (cl-incf changed))))))
    changed))

(defun my/lifeos--read-breakdown-titles ()
  "Read additional leaf task titles until the user enters an empty title."
  (let (titles title)
    (while (not (string-empty-p
                 (setq title (read-string "Additional leaf (empty to finish): "))))
      (push title titles))
    (nreverse titles)))

(defun my/lifeos-break-down-task
    (container-title first-leaf-title additional-titles &optional sequential rewire)
  "Break the current executable task into leaf tasks under a plain container.

CONTAINER-TITLE names the new aggregate heading. FIRST-LEAF-TITLE renames the
existing task while preserving its ID, clocks, metadata, and prerequisite
links. ADDITIONAL-TITLES become newly scaffolded tasks. When SEQUENTIAL is
non-nil, each new leaf depends on the preceding leaf. When REWIRE is non-nil,
existing downstream links to the original task are moved to the final leaf.
Modified buffers are not saved."
  (interactive
   (progn
     (org-back-to-heading t)
     (let* ((title (my/lifeos--clean-supertag-title
                    (org-get-heading t t t t) "task"))
            (container (read-string "Container title: " title))
            (first (read-string "Existing leaf title: " title))
            (additional (my/lifeos--read-breakdown-titles))
            (sequential (and additional
                             (y-or-n-p "Make the leaves a dependency chain? ")))
            (rewire (and additional
                         (y-or-n-p
                          "Move downstream dependencies to the final leaf? "))))
       (list container first additional sequential rewire))))
  (org-back-to-heading t)
  (unless (my/lifeos-executable-leaf-p)
    (user-error "Current heading must be an executable leaf #task"))
  (unless (and (stringp container-title)
               (not (string-empty-p (string-trim container-title)))
               (stringp first-leaf-title)
               (not (string-empty-p (string-trim first-leaf-title)))
               additional-titles)
    (user-error "Task breakdown requires a container and at least two leaves"))
  (when (and (org-clock-is-active)
             (markerp org-clock-marker)
             (marker-buffer org-clock-marker))
    (user-error "Clock out before breaking down a task"))
  (let* ((level (org-outline-level))
         (child-level (1+ level))
         (old-id (or (org-entry-get nil "ID") (org-id-get-create)))
         (old-marker (copy-marker (line-beginning-position) t))
         leaf-records)
    (atomic-change-group
      (beginning-of-line)
      (insert (make-string level ?*) " " (string-trim container-title) "\n")
      (goto-char old-marker)
      (org-demote-subtree)
      (org-edit-headline
       (concat (string-trim first-leaf-title) " #task"))
      (push (list :id old-id
                  :title (string-trim first-leaf-title)
                  :marker (copy-marker (point)))
            leaf-records)
      (dolist (title additional-titles)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n"))
        (insert (make-string child-level ?*) " TODO "
                (string-trim title) " #task\n")
        (forward-line -1)
        (let ((id (my/lifeos-scaffold-task)))
          (push (list :id id
                      :title (string-trim title)
                      :marker (copy-marker (line-beginning-position)))
                leaf-records))))
    (setq leaf-records (nreverse leaf-records))
    (let* ((last-record (car (last leaf-records)))
           (rewired (if rewire
                        (my/lifeos--rewire-dependency-target
                         old-id (plist-get last-record :id))
                      0)))
      (when sequential
        (cl-loop for previous in leaf-records
                 for current in (cdr leaf-records)
                 do (with-current-buffer
                        (marker-buffer (plist-get current :marker))
                      (save-excursion
                        (goto-char (plist-get current :marker))
                        (my/lifeos--insert-dependency
                         (plist-get previous :id)
                         (plist-get previous :title))))))
      (org-id-update-id-locations org-agenda-files)
      (when my/lifeos-diagnostics-mode
        (my/lifeos-refresh-buffer-diagnostics))
      (goto-char (plist-get (car leaf-records) :marker))
      (message "Created %d task leaves; rewired %d downstream link(s)"
               (length leaf-records) rewired)
      (list :container container-title
            :leaves leaf-records
            :rewired rewired))))

(defun my/lifeos--active-blockers ()
  "Return unresolved dependency descriptions for the task at point."
  (delq
   nil
   (mapcar
    (lambda (target)
      (let ((marker (org-id-find target 'marker)))
        (if (not marker)
            (format "%s (missing)" target)
          (with-current-buffer (marker-buffer marker)
            (save-excursion
              (goto-char marker)
              (let ((state (org-get-todo-state)))
                (unless (member state '("DONE" "CANCELLED"))
                  (format "%s (%s)"
                          (org-get-heading t t t t)
                          (or state "no state")))))))))
    (my/lifeos--dependency-targets))))

(defun my/lifeos-block-dependent-state-change (change)
  "Block inappropriate task state CHANGE while dependencies are active."
  (if (and (eq (plist-get change :type) 'todo-state-change)
           (member (plist-get change :to) '("NEXT" "DONE")))
      (save-excursion
        (goto-char (plist-get change :position))
        (let ((descendants (and (my/lifeos--heading-has-supertag-p "task")
                                (my/lifeos--todo-descendant-headings)))
              (blockers (my/lifeos--active-blockers)))
          (cond
           (descendants
            (message "Aggregate #task cannot enter %s; TODO descendants: %s"
                     (plist-get change :to)
                     (string-join descendants ", "))
            nil)
           (blockers
            (message "Blocked by: %s" (string-join blockers ", "))
            nil)
           (t t))))
    t))

(add-hook 'org-blocker-hook #'my/lifeos-block-dependent-state-change)

(defun my/lifeos--select-task-from-query (prompt query)
  "Visit a task selected with PROMPT from Supertag QUERY."
  (require 'supertag)
  (let* ((ids (seq-filter
               (lambda (id)
                 (my/lifeos--task-id-eligible-p
                  id '("TODO" "NEXT" "WAITING")))
               (supertag-query-node-ids query)))
         (candidates
          (mapcar (lambda (id)
                    (cons (plist-get (supertag-node-get id) :title) id))
                  ids))
         (title (completing-read prompt candidates nil t))
         (id (cdr (assoc title candidates)))
         (marker (and id (org-id-find id 'marker))))
    (unless marker
      (user-error "No matching task"))
    (pop-to-buffer (marker-buffer marker))
    (goto-char marker)
    (org-show-context)))

(defun my/lifeos-open-ready-task ()
  "Select and visit a ready task."
  (interactive)
  (my/lifeos--select-task-from-query
   "Ready task: "
   '(and (tag "task")
         (todo "TODO" "NEXT")
         (not (link "depends-on" (not (todo "DONE" "CANCELLED")))))))

(defun my/lifeos-open-blocked-task ()
  "Select and visit a blocked task."
  (interactive)
  (my/lifeos--select-task-from-query
   "Blocked task: "
   '(and (tag "task")
         (todo "TODO" "NEXT" "WAITING")
         (link "depends-on" (not (todo "DONE" "CANCELLED"))))))

(defun my/lifeos--duration-minutes (duration)
  "Convert a non-negative H:MM DURATION to integer minutes."
  (unless (my/lifeos--valid-effort-p duration)
    (error "Invalid H:MM duration: %s" duration))
  (my/lifeos--effort-minutes duration))

(defun my/lifeos--format-minutes (minutes)
  "Format signed MINUTES as H:MM."
  (let ((sign (if (< minutes 0) "-" ""))
        (absolute (abs minutes)))
    (format "%s%d:%02d" sign (/ absolute 60) (% absolute 60))))

(defun my/lifeos--week-marker (week-start)
  "Return the planning.org heading marker for WEEK-START."
  (let ((file (expand-file-name "planning.org" org-directory)))
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (catch 'week
           (org-map-entries
            (lambda ()
              (when (equal (org-entry-get nil "WEEK_START") week-start)
                (throw 'week (copy-marker (point)))))
            nil 'file)
           nil))))))

(defun my/lifeos--planning-heading-marker (title)
  "Return a marker for exact heading TITLE in planning.org."
  (let ((file (expand-file-name "planning.org" org-directory)))
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (when (re-search-forward
                (format "^\\*+ %s[[:space:]]*$" (regexp-quote title)) nil t)
           (beginning-of-line)
           (copy-marker (point))))))))

(defun my/lifeos--table-rows-under (marker heading)
  "Return normalized table rows below HEADING in MARKER's subtree."
  (with-current-buffer (marker-buffer marker)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char marker)
        (org-narrow-to-subtree)
        (unless (re-search-forward
                 (format "^\\*+ %s[[:space:]]*$" (regexp-quote heading)) nil t)
          (error "Missing %s table" heading))
        (unless (re-search-forward "^|" nil t)
          (error "Missing %s table" heading))
        (delq
         nil
         (mapcar
          (lambda (row)
            (when (listp row)
              (mapcar (lambda (cell)
                        (string-trim (substring-no-properties cell)))
                      row)))
          (org-table-to-lisp)))))))

(defun my/lifeos--heading-under-p (marker heading)
  "Return non-nil when HEADING exists in MARKER's subtree."
  (and marker
       (marker-buffer marker)
       (with-current-buffer (marker-buffer marker)
         (save-excursion
           (save-restriction
             (widen)
             (goto-char marker)
             (org-narrow-to-subtree)
             (re-search-forward
              (format "^\\*+ %s[[:space:]]*$" (regexp-quote heading)) nil t))))))

(defun my/lifeos--selector-valid-p (selector)
  "Return non-nil when SELECTOR belongs to the restricted LifeOS language."
  (pcase selector
    ((or `(tag ,(pred stringp))
         `(project-tag ,(pred stringp))
         `(project-id ,(pred stringp))
         `(work-mode ,(pred stringp))
         `(calendar-role ,(pred stringp))
         `(source task)
         `(prop ,(pred stringp) ,(pred stringp))
         `(project-prop ,(pred stringp) ,(pred stringp))) t)
    (`(,(or 'and 'or) . ,children)
     (and children (seq-every-p #'my/lifeos--selector-valid-p children)))
    (`(not ,child) (my/lifeos--selector-valid-p child))
    (_ nil)))

(defun my/lifeos-read-selector (text)
  "Read and validate one restricted selector from TEXT without evaluation."
  (let ((read-eval nil))
    (condition-case error-data
        (pcase-let* ((`(,selector . ,position) (read-from-string text))
                     (rest (string-trim (substring text position))))
          (unless (string-empty-p rest)
            (error "Trailing selector input: %s" rest))
          (unless (my/lifeos--selector-valid-p selector)
            (error "Unsupported LifeOS selector: %S" selector))
          selector)
      (end-of-file (error "Incomplete LifeOS selector: %s" text))
      (invalid-read-syntax
       (error "Invalid LifeOS selector: %s" (error-message-string error-data))))))

(defun my/lifeos--record-at-marker (record function)
  "Call FUNCTION at RECORD's live marker, returning nil without one."
  (when-let* ((marker (plist-get record :marker))
              ((markerp marker))
              ((marker-buffer marker)))
    (with-current-buffer (marker-buffer marker)
      (save-excursion
        (goto-char marker)
        (funcall function)))))

(defun my/lifeos--heading-selector-tags ()
  "Return ordinary and textual supertags on the heading at point."
  (let ((tags (copy-sequence (org-get-tags nil t)))
        (heading (org-get-heading t t t t))
        (start 0))
    (while (string-match "\\(?:^\\|[[:space:]]\\)#\\([[:alnum:]_-]+\\)" heading start)
      (push (match-string 1 heading) tags)
      (setq start (match-end 0)))
    (delete-dups tags)))

(defun my/lifeos--entry-selector-properties ()
  "Return current heading properties as string pairs."
  (mapcar (lambda (entry) (cons (car entry) (cdr entry)))
          (org-entry-properties nil 'standard)))

(defun my/lifeos-selector-match-p (selector source)
  "Return non-nil when restricted SELECTOR matches SOURCE evidence.
SOURCE is a task or calendar plist with `:source-type'."
  (unless (my/lifeos--selector-valid-p selector)
    (error "Unsupported LifeOS selector: %S" selector))
  (when source
    (let ((source-type (or (plist-get source :source-type) 'task)))
    (pcase selector
      (`(tag ,tag)
       (and (eq source-type 'task) (member tag (plist-get source :tags))))
      (`(project-tag ,tag)
       (and (eq source-type 'task)
            (member tag (plist-get source :project-tags))))
      (`(project-id ,id)
       (and (eq source-type 'task) (equal (plist-get source :project-id) id)))
      (`(prop ,property ,value)
       (and (eq source-type 'task)
            (equal (alist-get property (plist-get source :properties)
                              nil nil #'equal)
                   value)))
      (`(project-prop ,property ,value)
       (and (eq source-type 'task)
            (equal (alist-get property (plist-get source :project-properties)
                              nil nil #'equal)
                   value)))
      (`(work-mode ,mode)
       (and (eq source-type 'task) (equal (plist-get source :work-mode) mode)))
      (`(calendar-role ,role)
       (and (eq source-type 'calendar)
            (equal (plist-get source :calendar-role) role)))
      (`(source task) (eq source-type 'task))
      (`(and . ,children)
       (seq-every-p (lambda (child) (my/lifeos-selector-match-p child source))
                    children))
      (`(or . ,children)
       (seq-some (lambda (child) (my/lifeos-selector-match-p child source))
                 children))
        (`(not ,child) (not (my/lifeos-selector-match-p child source)))))))

(defun my/lifeos-intentions-for-week (week-start)
  "Return the selected five-column Intentions rows for WEEK-START.
A matching weekly table replaces recurring rows.  Return nil when unconfigured."
  (let* ((weekly (my/lifeos--week-marker week-start))
         (defaults (my/lifeos--planning-heading-marker "Recurring defaults"))
         (marker (cond ((my/lifeos--heading-under-p weekly "Intentions") weekly)
                       ((my/lifeos--heading-under-p defaults "Intentions") defaults))))
    (when marker
      (let ((rows (my/lifeos--table-rows-under marker "Intentions"))
            (seen (make-hash-table :test #'equal))
            intentions)
        (unless (equal (car rows) '("Name" "Min" "Target" "Max" "Selector"))
          (error "Intentions header must be exactly | Name | Min | Target | Max | Selector |"))
        (dolist (row (cdr rows) (nreverse intentions))
          (unless (= (length row) 5)
            (error "Intentions row must contain exactly 5 cells: %S" row))
          (pcase-let* ((`(,name ,minimum-text ,target-text ,maximum-text ,selector-text) row)
                       (selector (my/lifeos-read-selector selector-text))
                       (minimum (unless (string-empty-p minimum-text)
                                  (my/lifeos--duration-minutes minimum-text)))
                       (target (unless (string-empty-p target-text)
                                 (my/lifeos--duration-minutes target-text)))
                       (maximum (unless (string-empty-p maximum-text)
                                  (my/lifeos--duration-minutes maximum-text)))
                       (id (concat "intention:" (secure-hash 'sha1
                                                             (concat name "\0" selector-text)))))
            (when (or (string-empty-p name) (string-empty-p selector-text))
              (error "Intention name and selector cannot be empty"))
            (when (or (and minimum target (> minimum target))
                      (and target maximum (> target maximum))
                      (and minimum maximum (> minimum maximum)))
              (error "Intention bounds are out of order: %s" name))
            (when (gethash id seen) (error "Duplicate intention ID: %s" id))
            (puthash id t seen)
            (push (list :id id :name name :minimum minimum :target target
                        :maximum maximum :selector selector
                        :selector-text selector-text :marker marker)
                  intentions)))))))

(defun my/lifeos-matching-intentions (source intentions)
  "Return names of INTENTIONS whose selectors match SOURCE independently."
  (mapcar (lambda (intention) (plist-get intention :name))
          (seq-filter (lambda (intention)
                        (my/lifeos-selector-match-p
                         (plist-get intention :selector) source))
                      intentions)))

(defun my/lifeos--date-add-days (date days)
  "Return the YYYY-MM-DD that is DAYS after DATE."
  (unless (string-match
           "\\`\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)\\'" date)
    (error "Invalid date: %s" date))
  (let* ((gregorian (list (string-to-number (match-string 2 date))
                          (string-to-number (match-string 3 date))
                          (string-to-number (match-string 1 date))))
         (result (calendar-gregorian-from-absolute
                  (+ days (calendar-absolute-from-gregorian gregorian)))))
    (format "%04d-%02d-%02d" (nth 2 result) (car result) (nth 1 result))))

(defun my/lifeos--date-time (date clock)
  "Return local time for YYYY-MM-DD DATE and HH:MM CLOCK."
  (org-time-string-to-time (format "<%s %s>" date clock)))

(defun my/lifeos--end-of-date (date)
  "Return the final second of local DATE."
  (time-subtract (my/lifeos--date-time (my/lifeos--date-add-days date 1) "00:00")
                 (seconds-to-time 1)))

(defun my/lifeos--week-times (week-start)
  "Return start and exclusive end times for WEEK-START."
  (list (my/lifeos--date-time week-start "00:00")
        (my/lifeos--date-time (my/lifeos--date-add-days week-start 7) "00:00")))

(defun my/lifeos--calendar-range-at-point ()
  "Return the current calendar event's timed range, or nil for all-day events."
  (when-let* ((bounds (my/lifeos--entry-section-bounds)))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward
             "<\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)[^>\n]*[[:space:]]\\([0-9][0-9]\\):\\([0-9][0-9]\\)-\\([0-9][0-9]\\):\\([0-9][0-9]\\)>"
             (cdr bounds) t)
        (let* ((year (string-to-number (match-string 1)))
               (month (string-to-number (match-string 2)))
               (day (string-to-number (match-string 3)))
               (start (encode-time 0
                                   (string-to-number (match-string 5))
                                   (string-to-number (match-string 4))
                                   day month year))
               (end (encode-time 0
                                 (string-to-number (match-string 7))
                                 (string-to-number (match-string 6))
                                 day month year)))
          (when (time-less-p end start)
            (setq end (time-add end (days-to-time 1))))
          (cons start end))))))

(defun my/lifeos--direct-clocked-minutes-in-range (record start end)
  "Return direct clock minutes for RECORD between START and END."
  (or (my/lifeos--record-at-marker
       record
       (lambda ()
         (when-let* ((bounds (my/lifeos--entry-section-bounds)))
           (save-restriction
             (narrow-to-region (line-beginning-position) (cdr bounds))
             (org-clock-sum start end)
             org-clock-file-total-minutes))))
      0))

(defun my/lifeos--calendar-intention-minutes (selector start end)
  "Return timed calendar minutes in START..END matching SELECTOR."
  (let ((file (expand-file-name "calendar.org" org-directory)) (total 0))
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-map-entries
          (lambda ()
            (when-let* ((range (my/lifeos--calendar-range-at-point))
                        (source (list :source-type 'calendar
                                      :calendar-role
                                      (org-entry-get nil "CALENDAR_ROLE")
                                      :marker (copy-marker (point))))
                        ((my/lifeos-selector-match-p selector source))
                        (overlap-start (if (time-less-p (car range) start)
                                           start (car range)))
                        (overlap-end (if (time-less-p end (cdr range))
                                         end (cdr range)))
                        ((time-less-p overlap-start overlap-end)))
              (cl-incf total (round (/ (float-time
                                         (time-subtract overlap-end overlap-start))
                                        60)))))
          nil 'file))))
    total))

(defun my/lifeos-intention-ledger (week-start &optional forecast analysis)
  "Return independent intention accounting rows for WEEK-START.
FORECAST contributes fixed and proposed placements; ANALYSIS supplies task records."
  (let* ((intentions (my/lifeos-intentions-for-week week-start))
         (analysis (or analysis (my/lifeos-graph-analysis)))
         (records (plist-get analysis :all-records))
         (by-id (plist-get analysis :by-id)))
    (pcase-let ((`(,start ,end) (my/lifeos--week-times week-start)))
      (mapcar
       (lambda (intention)
         (let* ((selector (plist-get intention :selector))
                (matches (seq-filter
                          (lambda (record)
                            (my/lifeos-selector-match-p selector record)) records))
                (remaining (seq-reduce
                            (lambda (sum record)
                              (+ sum (or (and (member (plist-get record :state)
                                                       '("TODO" "NEXT" "WAITING"))
                                               (plist-get record :minutes)) 0)))
                            matches 0))
                (clocked (seq-reduce
                          (lambda (sum record)
                            (+ sum (my/lifeos--direct-clocked-minutes-in-range
                                    record start end))) matches 0))
                (calendar (my/lifeos--calendar-intention-minutes
                           selector start end))
                (actual (+ clocked calendar))
                (fixed 0) (proposed 0))
           (dolist (placement (plist-get forecast :placements))
             (when (and (not (time-less-p (plist-get placement :start) start))
                        (time-less-p (plist-get placement :start) end)
                        (my/lifeos-selector-match-p
                         selector (gethash (plist-get placement :id) by-id)))
               (if (eq (plist-get placement :kind) 'fixed)
                   (cl-incf fixed (plist-get placement :minutes))
                 (cl-incf proposed (plist-get placement :minutes)))))
           (list :id (plist-get intention :id) :name (plist-get intention :name)
                 :selector (plist-get intention :selector-text)
                 :minimum (plist-get intention :minimum)
                 :target (plist-get intention :target)
                 :maximum (plist-get intention :maximum)
                  :remaining remaining :clocked clocked :calendar calendar
                  :actual actual :fixed fixed
                 :proposed proposed
                 :target-remaining (and (plist-get intention :target)
                                        (- (plist-get intention :target)
                                            actual fixed proposed)))))
       intentions))))

(defun my/lifeos-remaining-by-intention (week-start &optional analysis)
  "Return intention names, selectors, and remaining work for WEEK-START."
  (mapcar (lambda (row)
            (list (plist-get row :name) (plist-get row :selector)
                  (plist-get row :remaining)))
          (my/lifeos-intention-ledger week-start nil analysis)))

(defun org-dblock-write:lifeos-remaining-by-intention (params)
  "Write selector-based remaining work for dynamic block PARAMS."
  (let ((week-start (plist-get params :week)))
    (unless (stringp week-start)
      (error "lifeos-remaining-by-intention requires :week YYYY-MM-DD"))
    (if-let* ((rows (my/lifeos-remaining-by-intention week-start)))
        (progn
          (insert "| Intention | Selector | Remaining |\n|-----------+----------+-----------|\n")
          (dolist (row rows)
            (insert (format "| %s | %s | %s |\n" (nth 0 row) (nth 1 row)
                            (my/lifeos--format-minutes (nth 2 row)))))
          (org-table-align))
      (insert "No allocation targets are configured.\n"))))

(defun org-dblock-write:lifeos-intention-ledger (params)
  "Write the selector-based weekly intention ledger described by PARAMS."
  (let* ((week-start (plist-get params :week))
         (forecast (and (stringp week-start) (fboundp 'my/lifeos-build-forecast)
                        (my/lifeos-build-forecast week-start 1)))
         (rows (and (stringp week-start)
                    (my/lifeos-intention-ledger week-start forecast))))
    (unless (stringp week-start)
      (error "lifeos-intention-ledger requires :week YYYY-MM-DD"))
    (if (null rows)
        (insert "No allocation targets are configured.\n")
      (insert "Rows are independent views; overlapping selectors may credit the same work.\n\n")
      (insert "| Intention | Selector | Min | Target | Max | Remaining | Clocked | Calendar | Fixed | Proposed | To target |\n")
      (insert "|-----------+----------+-----+--------+-----+-----------+---------+----------+-------+----------+-----------|\n")
      (dolist (row rows)
        (insert (format "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n"
                        (plist-get row :name) (plist-get row :selector)
                        (if-let* ((v (plist-get row :minimum))) (my/lifeos--format-minutes v) "")
                        (if-let* ((v (plist-get row :target))) (my/lifeos--format-minutes v) "")
                        (if-let* ((v (plist-get row :maximum))) (my/lifeos--format-minutes v) "")
                        (my/lifeos--format-minutes (plist-get row :remaining))
                        (my/lifeos--format-minutes (plist-get row :clocked))
                        (my/lifeos--format-minutes (plist-get row :calendar))
                        (my/lifeos--format-minutes (plist-get row :fixed))
                        (my/lifeos--format-minutes (plist-get row :proposed))
                        (if-let* ((v (plist-get row :target-remaining)))
                            (my/lifeos--format-minutes v) ""))))
      (org-table-align))))

(defun my/lifeos--clean-supertag-title (title tag)
  "Remove trailing hashtag TAG from TITLE."
  (string-trim
   (replace-regexp-in-string
    (format "[[:space:]]+#%s\\(?:[[:space:]]+\\|\\'\\)" (regexp-quote tag))
     " " title)))

(defun my/lifeos--heading-key ()
  "Return a transient stable key for the heading at point."
  (or (when-let* ((id (org-entry-get nil "ID")))
        (concat "id:" id))
      (list (if buffer-file-name
                (file-truename buffer-file-name)
              (buffer-name))
            (line-beginning-position))))

(defun my/lifeos--project-record-at-point ()
  "Return metadata for the #project heading at point."
  (let ((state (org-get-todo-state)))
    (list :id (org-entry-get nil "ID")
          :key (my/lifeos--heading-key)
          :title (my/lifeos--clean-supertag-title
                  (org-get-heading t t t t) "project")
          :state state
          :commitment (if (member state '("SOMEDAY" "DONE" "CANCELLED"))
                          'uncommitted
                        'committed)
          :deadline (org-entry-get nil "DEADLINE")
          :project-effort (org-entry-get nil "PROJECT_EFFORT")
          :default-work-mode (org-entry-get nil "DEFAULT_WORK_MODE")
           :planning-chunk (org-entry-get nil "PLANNING_CHUNK")
           :estimate-confidence (org-entry-get nil "ESTIMATE_CONFIDENCE")
           :tags (my/lifeos--heading-selector-tags)
           :properties (my/lifeos--entry-selector-properties)
           :marker (copy-marker (point)))))

(defun my/lifeos--task-record-at-point ()
  "Return the canonical task record for the #task heading at point."
  (let* ((diagnostics (my/lifeos-task-diagnostics))
         (project (my/lifeos--project-at-point))
         (own-deadline (org-entry-get nil "DEADLINE"))
         (balance (my/lifeos-task-estimate-balance)))
    (list :id (org-entry-get nil "ID")
          :title (my/lifeos--clean-supertag-title
                  (org-get-heading t t t t) "task")
          :state (org-get-todo-state)
          :effort-minutes (my/lifeos--effort-minutes
                           (org-entry-get nil "EFFORT"))
          :minutes (and balance (> balance 0) balance)
          :balance balance
          :source-type 'task
          :tags (my/lifeos--heading-selector-tags)
          :properties (my/lifeos--entry-selector-properties)
          :project-tags (plist-get project :tags)
          :project-properties (plist-get project :properties)
          :work-mode (org-entry-get nil "WORK_MODE")
          :priority (org-entry-get nil "PRIORITY")
          :impact (org-entry-get nil "IMPACT")
          :deadline (my/lifeos--earlier-deadline
                     own-deadline (plist-get project :deadline))
          :project-id (plist-get project :id)
          :project-key (plist-get project :key)
          :project-title (plist-get project :title)
          :project-deadline (plist-get project :deadline)
          :targets (my/lifeos--dependency-targets)
          :scheduled (my/lifeos--timed-scheduled-time-at-point)
          :executable (my/lifeos-executable-leaf-p)
          :diagnostics diagnostics
          :eligible (not (my/lifeos--diagnostics-have-severity-p
                          diagnostics 'error))
          :marker (copy-marker (point)))))

(defun my/lifeos--project-at-point ()
  "Return nearest project metadata for the task at point."
  (save-excursion
    (catch 'project
      (while (org-up-heading-safe)
         (when (my/lifeos--heading-has-supertag-p "project")
           (throw 'project (my/lifeos--project-record-at-point))))
       nil)))

(defun my/lifeos--project-records ()
  "Return records for all #project headings in agenda files."
  (let (records)
    (dolist (file (delete-dups (copy-sequence org-agenda-files)))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (org-map-entries
            (lambda ()
              (when (my/lifeos--heading-has-supertag-p "project")
                (push (my/lifeos--project-record-at-point) records)))
            nil 'file)))))
    (nreverse records)))

(defun my/lifeos--aligned-positive-duration-minutes (value)
  "Return VALUE in minutes when it is positive and aligned to 15 minutes."
  (when-let* ((minutes (my/lifeos--effort-minutes value))
              ((> minutes 0))
              ((zerop (% minutes 15))))
    minutes))

(defun my/lifeos--valid-project-deadline-p (deadline)
  "Return non-nil when DEADLINE is a parseable Org timestamp."
  (and (stringp deadline)
       (> (length deadline) 2)
       (memq (aref deadline 0) '(?< ?\[))
       (memq (aref deadline (1- (length deadline))) '(?> ?\]))
       (string-match-p
        "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" deadline)
       (condition-case nil
           (progn (org-time-string-to-time deadline) t)
         (error nil))))

(defun my/lifeos--unresolved-project-descendants (project)
  "Return active descendant work in PROJECT that is not a valid task leaf."
  (let ((marker (plist-get project :marker)) unresolved)
    (when (and (markerp marker) (marker-buffer marker))
      (with-current-buffer (marker-buffer marker)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char marker)
            (let ((end (save-excursion (org-end-of-subtree t t) (point))))
              (forward-line 1)
              (while (re-search-forward org-outline-regexp-bol end t)
                (goto-char (match-beginning 0))
                (when (and (member (org-get-todo-state)
                                   '("TODO" "NEXT" "WAITING"))
                           (not (and (my/lifeos-executable-leaf-p)
                                     (not (my/lifeos--diagnostics-have-severity-p
                                           (my/lifeos-task-diagnostics)
                                           'error)))))
                  (push (list :title (org-get-heading t t t t)
                              :marker (copy-marker (point)))
                        unresolved))
                (forward-line 1)))))))
    (nreverse unresolved)))

(defun my/lifeos--project-definition-record (project task-records)
  "Add definition diagnostics and effort accounting to PROJECT."
  (let* ((project-key (plist-get project :key))
         (descendants
          (seq-filter (lambda (record)
                        (equal (plist-get record :project-key) project-key))
                      task-records))
         (project-minutes
          (my/lifeos--aligned-positive-duration-minutes
           (plist-get project :project-effort)))
         (allocated-minutes
          (seq-reduce
           (lambda (total record)
             (+ total (or (and (plist-get record :executable)
                               (plist-get record :effort-minutes))
                          0)))
           descendants 0))
         (explicit-remaining-minutes
          (seq-reduce
           (lambda (total record)
             (+ total
                (or (and (plist-get record :executable)
                         (member (plist-get record :state)
                                 '("TODO" "NEXT" "WAITING"))
                         (plist-get record :minutes))
                    0)))
           descendants 0))
         (unallocated-minutes
          (and project-minutes (max (- project-minutes allocated-minutes) 0)))
         (overallocated-minutes
          (and project-minutes (max (- allocated-minutes project-minutes) 0)))
         (unresolved-descendants
          (my/lifeos--unresolved-project-descendants project))
         (diagnostics
          (delq
           nil
           (list
            (unless (and (plist-get project :id)
                         (not (string-empty-p (plist-get project :id))))
              (my/lifeos--diagnostic 'missing-project-id 'error
                                     "Project requires an ID"))
            (unless (my/lifeos--valid-project-deadline-p
                     (plist-get project :deadline))
              (my/lifeos--diagnostic 'invalid-project-deadline 'error
                                     "Project requires a parseable DEADLINE"))
            (unless project-minutes
              (my/lifeos--diagnostic
               'invalid-project-effort 'error
               "PROJECT_EFFORT must be a positive 15-minute-aligned H:MM duration"))
            (when (and overallocated-minutes (> overallocated-minutes 0))
              (my/lifeos--diagnostic
               'project-effort-overallocated 'error
               "Executable task effort exceeds PROJECT_EFFORT"
               (list :project-effort project-minutes
                     :explicit-effort allocated-minutes)))
            (when unresolved-descendants
              (my/lifeos--diagnostic
               'unresolved-descendant-work 'error
               "Active descendant work must be valid executable #task leaves"
               (mapcar (lambda (record) (plist-get record :title))
                       unresolved-descendants)))
            (when (and unallocated-minutes (> unallocated-minutes 0)
                       (not (member (plist-get project :default-work-mode)
                                    my/lifeos-work-mode-values)))
              (my/lifeos--diagnostic
               'invalid-default-work-mode 'error
               "DEFAULT_WORK_MODE must be a recognized work mode"))
            (when (and unallocated-minutes (> unallocated-minutes 0)
                       (not (my/lifeos--aligned-positive-duration-minutes
                             (plist-get project :planning-chunk))))
              (my/lifeos--diagnostic
               'invalid-planning-chunk 'error
               "PLANNING_CHUNK must be a positive 15-minute-aligned H:MM duration"))
            (when (and unallocated-minutes (> unallocated-minutes 0)
                        (not (member (plist-get project :estimate-confidence)
                                     my/lifeos-estimate-confidence-values)))
              (my/lifeos--diagnostic
               'invalid-estimate-confidence 'error
               "ESTIMATE_CONFIDENCE must be Low, Medium, or High"))))))
    (setq project (copy-sequence project))
    (plist-put project :project-effort-minutes project-minutes)
    (plist-put project :explicit-effort-minutes allocated-minutes)
    (plist-put project :explicit-remaining-minutes explicit-remaining-minutes)
    (plist-put project :unallocated-effort-minutes unallocated-minutes)
    (plist-put project :overallocated-effort-minutes overallocated-minutes)
    (plist-put project :remaining-effort-minutes
               (and unallocated-minutes
                    (+ explicit-remaining-minutes unallocated-minutes)))
    (plist-put project :unresolved-descendants unresolved-descendants)
    (plist-put project :diagnostics diagnostics)
    (plist-put project :definition-status
               (cond (diagnostics 'incomplete)
                     ((> unallocated-minutes 0) 'coarse)
                     (t 'detailed)))
    project))

(defun my/lifeos-project-record-at-point ()
  "Return the current explicit project with canonical local diagnostics."
  (save-excursion
    (org-back-to-heading t)
    (unless (my/lifeos--heading-has-supertag-p "project")
      (user-error "Point is not on an explicit #project heading"))
    (let* ((project (my/lifeos--project-record-at-point))
           (end (save-excursion (org-end-of-subtree t t) (point)))
           task-records)
      (forward-line 1)
      (while (re-search-forward org-outline-regexp-bol end t)
        (goto-char (match-beginning 0))
        (when (my/lifeos--heading-has-supertag-p "task")
          (push (my/lifeos--task-record-at-point) task-records))
        (forward-line 1))
      (my/lifeos--project-definition-record project (nreverse task-records)))))

(defun my/lifeos--project-inventory (task-records)
  "Return canonical project and unresolved-work inventory for TASK-RECORDS."
  (let ((projects (mapcar (lambda (project)
                            (my/lifeos--project-definition-record
                             project task-records))
                          (my/lifeos--project-records)))
        (orphan-records
         (seq-filter (lambda (record)
                       (and (plist-get record :executable)
                            (null (plist-get record :project-key))))
                     task-records)))
    (list :projects projects
          :orphan-records orphan-records)))

(defun my/lifeos--earlier-deadline (first second)
  "Return the earlier Org deadline string from FIRST and SECOND."
  (cond
   ((null first) second)
   ((null second) first)
   ((time-less-p (org-time-string-to-time first)
                 (org-time-string-to-time second))
    first)
   (t second)))

(defun my/lifeos--task-records ()
  "Return metadata records for all #task headings in agenda files."
  (let (records)
    (dolist (file (delete-dups (copy-sequence org-agenda-files)))
      (when (file-readable-p file)
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (org-map-entries
             (lambda ()
               (when (my/lifeos--heading-has-supertag-p "task")
                 (push (my/lifeos--task-record-at-point) records)))
            nil 'file)))))
    (nreverse records)))

(defun my/lifeos--graph-cycles (edges)
  "Return cycle paths from dependency EDGES."
  (let (cycles)
    (dolist (entry edges)
      (dolist (target (cdr entry))
        (when-let* ((path (my/lifeos--dependency-path
                           target (car entry) edges)))
          (push (cons (car entry) path) cycles))))
    cycles))

(defun my/lifeos--topological-order (ids edges)
  "Return prerequisite-first order for IDS and dependency EDGES."
  (let ((indegree (make-hash-table :test #'equal))
        (dependents (make-hash-table :test #'equal))
        queue order)
    (dolist (id ids)
      (puthash id (length (alist-get id edges nil nil #'equal)) indegree))
    (dolist (entry edges)
      (dolist (target (cdr entry))
        (push (car entry) (gethash target dependents))))
    (dolist (id ids)
      (when (zerop (gethash id indegree))
        (push id queue)))
    (setq queue (sort queue #'string<))
    (while queue
      (let ((id (pop queue)))
        (push id order)
        (dolist (dependent (gethash id dependents))
          (let ((next (1- (gethash dependent indegree))))
            (puthash dependent next indegree)
            (when (zerop next)
              (push dependent queue)
              (setq queue (sort queue #'string<)))))))
    (let ((result (nreverse order)))
      (and (= (length result) (length ids)) result))))

(defun my/lifeos-graph-analysis ()
  "Return active task graph structure and integrity diagnostics."
  (org-id-update-id-locations org-agenda-files)
  (let* ((records (my/lifeos--task-records))
         (inventory (my/lifeos--project-inventory records))
         (by-id (make-hash-table :test #'equal))
         (active-states '("TODO" "NEXT" "WAITING"))
          active-records invalid-records active-ids edges missing inactive invalid)
    (dolist (record records)
      (when-let* ((id (plist-get record :id)))
        (puthash id record by-id)))
    (setq active-records
          (seq-filter (lambda (record)
                        (and (plist-get record :id)
                             (plist-get record :eligible)
                             (member (plist-get record :state) active-states)))
                      records)
          invalid-records
          (seq-filter (lambda (record)
                        (and (member (plist-get record :state) active-states)
                             (not (plist-get record :eligible))))
                      records)
          active-ids (mapcar (lambda (record) (plist-get record :id))
                             active-records))
    (dolist (record active-records)
      (let ((source (plist-get record :id)) known-targets)
        (dolist (target (plist-get record :targets))
          (let ((target-record (gethash target by-id)))
            (cond
             ((null target-record) (push (cons source target) missing))
             ((not (plist-get target-record :eligible))
              (push (cons source target) invalid))
             ((member (plist-get target-record :state) '("DONE" "CANCELLED")))
             ((member (plist-get target-record :state) active-states)
              (push target known-targets))
             (t (push (cons source target) inactive)))))
        (push (cons source (nreverse known-targets)) edges)))
    (setq edges (nreverse edges))
    (let ((cycles (my/lifeos--graph-cycles edges)))
      (let ((valid-p (not (or cycles missing inactive invalid))))
        (list :projects (plist-get inventory :projects)
              :orphan-records (plist-get inventory :orphan-records)
              :all-records records
              :records active-records
             :invalid-records invalid-records
            :by-id by-id
            :edges edges
            :missing-targets (nreverse missing)
            :inactive-targets (nreverse inactive)
             :invalid-targets (nreverse invalid)
             :cycles cycles
              :valid-p valid-p
              :order (when valid-p
                       (my/lifeos--topological-order active-ids edges)))))))

(defun my/lifeos--deadline-date (deadline)
  "Return YYYY-MM-DD from Org DEADLINE, or an empty string."
  (if (and deadline
           (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" deadline))
      (match-string 0 deadline)
    ""))

(defun my/lifeos-critical-paths (&optional now analysis)
  "Return critical path records grouped by project and effective deadline."
  (let* ((analysis (or analysis (my/lifeos-graph-analysis)))
         (records (plist-get analysis :records))
         (by-id (plist-get analysis :by-id))
         (edges (plist-get analysis :edges))
         (order (plist-get analysis :order))
         (distance (make-hash-table :test #'equal))
         (paths (make-hash-table :test #'equal))
         (groups (make-hash-table :test #'equal))
         (now (or now (current-time))))
    (when order
      (dolist (id order)
        (let* ((record (gethash id by-id))
               (minutes (plist-get record :minutes))
               (targets (alist-get id edges nil nil #'equal))
               (best-target
                (car (sort (copy-sequence targets)
                           (lambda (first second)
                             (> (or (gethash first distance) -1)
                                (or (gethash second distance) -1))))))
               (best-distance (and best-target (gethash best-target distance))))
          (if (or (null minutes) (and best-target (null best-distance)))
              (puthash id nil distance)
            (puthash id (+ minutes (or best-distance 0)) distance)
            (puthash id (append (and best-target (gethash best-target paths))
                                (list id))
                     paths))))
      (dolist (record records)
        (let* ((id (plist-get record :id))
               (deadline (plist-get record :deadline))
               (key (list (or (plist-get record :project-id) "standalone")
                          (my/lifeos--deadline-date deadline)))
               (existing (gethash key groups))
               (minutes (gethash id distance)))
          (when (and minutes
                     (or (null existing)
                         (> minutes (plist-get existing :minutes))))
            (let* ((finish (time-add now (seconds-to-time (* minutes 60))))
                    (deadline-end
                     (and deadline
                          (my/lifeos--end-of-date
                           (my/lifeos--deadline-date deadline))))
                   (slack (and deadline-end
                               (floor (/ (float-time
                                          (time-subtract deadline-end finish))
                                         60)))))
              (puthash
               key
               (list :project (or (plist-get record :project-title)
                                  "Standalone")
                     :deadline (my/lifeos--deadline-date deadline)
                     :path (gethash id paths)
                     :minutes minutes
                     :continuous-finish finish
                     :continuous-slack slack)
               groups)))))
      (let (result)
        (maphash (lambda (_key value) (push value result)) groups)
        (sort result
              (lambda (first second)
                (string< (plist-get first :project)
                         (plist-get second :project))))))))

(defun org-dblock-write:lifeos-critical-paths (_params)
  "Write critical paths for active task projects."
  (let ((insertion-point (copy-marker (point)))
        (paths (my/lifeos-critical-paths))
        (analysis (my/lifeos-graph-analysis)))
    (goto-char insertion-point)
    (cond
     ((plist-get analysis :cycles)
      (insert "Dependency graph contains a cycle; critical paths are unknown.\n"))
     ((plist-get analysis :missing-targets)
       (insert "Dependency graph has missing targets; critical paths are unknown.\n"))
     ((plist-get analysis :invalid-targets)
      (insert "Dependency graph targets invalid tasks; critical paths are unknown.\n"))
     ((plist-get analysis :inactive-targets)
      (insert "Dependency graph targets inactive tasks; critical paths are unknown.\n"))
     (t
      (insert "| Project | Deadline | Critical chain | Duration | Continuous finish | Continuous slack |\n")
      (insert "|---------+----------+----------------+----------+-------------------+------------------|\n")
      (dolist (path paths)
        (let ((titles
               (mapcar (lambda (id)
                         (plist-get (gethash id (plist-get analysis :by-id)) :title))
                       (plist-get path :path))))
          (insert
           (format "| %s | %s | %s | %s | %s | %s |\n"
                   (plist-get path :project)
                   (plist-get path :deadline)
                   (string-join titles " -> ")
                   (my/lifeos--format-minutes (plist-get path :minutes))
                   (format-time-string "%Y-%m-%d %H:%M"
                                       (plist-get path :continuous-finish))
                   (if-let* ((slack (plist-get path :continuous-slack)))
                       (my/lifeos--format-minutes slack)
                     "unknown")))))
      (org-table-align)))
    (set-marker insertion-point nil)))

(defun my/lifeos--project-graph-problems (project-key analysis)
  "Return graph problems in ANALYSIS that affect PROJECT-KEY."
  (let ((by-id (plist-get analysis :by-id)) problems)
    (dolist (property '(:missing-targets :inactive-targets :invalid-targets))
      (dolist (edge (plist-get analysis property))
        (when (equal (plist-get (gethash (car edge) by-id) :project-key)
                     project-key)
          (push (list property edge) problems))))
    (dolist (cycle (plist-get analysis :cycles))
      (when (seq-some
             (lambda (id)
               (equal (plist-get (gethash id by-id) :project-key) project-key))
             cycle)
        (push (list :cycle cycle) problems)))
    (nreverse problems)))

(defun my/lifeos--project-summaries (analysis forecast &optional now)
  "Aggregate project indicators from shared ANALYSIS and FORECAST."
  (let ((summaries (make-hash-table :test #'equal))
        (placements-by-id (make-hash-table :test #'equal))
        (now (or now (current-time))))
    (dolist (project (plist-get analysis :projects))
      (puthash
       (plist-get project :key)
       (list :project-key (plist-get project :key)
             :project-title (plist-get project :title)
             :deadline (plist-get project :deadline)
             :done-count 0 :total-count 0 :left-minutes 0
             :unknown-records nil :active-count 0 :fixed-count 0
             :planned-count 0 :unplaced-count 0 :invalid-records nil
             :fixed-records nil :planned-records nil :unplaced-failures nil)
       summaries))
    (dolist (placement (plist-get forecast :placements))
      (when-let* ((id (plist-get placement :id)))
        (puthash id placement placements-by-id)))
    (dolist (record (plist-get analysis :all-records))
      (when-let* ((key (plist-get record :project-key))
                  (summary (gethash key summaries)))
        (let ((state (plist-get record :state))
              (active (member (plist-get record :state)
                              '("TODO" "NEXT" "WAITING"))))
          (when (and (plist-get record :executable)
                     (not (equal state "CANCELLED")))
            (plist-put summary :total-count
                       (1+ (plist-get summary :total-count)))
            (when (equal state "DONE")
              (plist-put summary :done-count
                         (1+ (plist-get summary :done-count)))))
           (when active
             (when (plist-get record :executable)
               (when-let* ((balance (plist-get record :balance))
                           ((> balance 0)))
                 (plist-put summary :left-minutes
                            (+ balance (plist-get summary :left-minutes))))
               (unless (plist-get record :minutes)
                 (push record (plist-get summary :unknown-records))))
             (unless (plist-get record :eligible)
              (push record (plist-get summary :invalid-records)))
            (when (and (plist-get record :eligible)
                       (plist-get record :executable))
              (plist-put summary :active-count
                         (1+ (plist-get summary :active-count)))
              (when (plist-get record :scheduled)
                (plist-put summary :fixed-count
                           (1+ (plist-get summary :fixed-count)))
                (push record (plist-get summary :fixed-records)))
              (when (gethash (plist-get record :id) placements-by-id)
                (plist-put summary :planned-count
                           (1+ (plist-get summary :planned-count)))
                (push record (plist-get summary :planned-records))))))))
    (dolist (record (plist-get forecast :data-errors))
      (when-let* ((key (plist-get record :project-key))
                  (summary (gethash key summaries))
                  ((not (seq-find
                         (lambda (existing)
                           (equal (plist-get existing :marker)
                                  (plist-get record :marker)))
                         (plist-get summary :invalid-records)))))
        (push record (plist-get summary :invalid-records))
        (push record (plist-get summary :unknown-records))))
    (dolist (failure (plist-get forecast :failures))
      (when-let* ((key (plist-get failure :project-key))
                  (summary (gethash key summaries)))
        (plist-put summary :unplaced-count
                   (1+ (plist-get summary :unplaced-count)))
        (push failure (plist-get summary :unplaced-failures))))
    (maphash
     (lambda (key summary)
       (let* ((graph-problems (my/lifeos--project-graph-problems key analysis))
              (deadline (plist-get summary :deadline))
              (complete-coverage
               (= (plist-get summary :planned-count)
                  (plist-get summary :active-count)))
              (unknown-p
               (or (null deadline)
                   (plist-get summary :invalid-records)
                   (plist-get summary :unknown-records)
                   graph-problems
                   (> (plist-get summary :unplaced-count) 0)
                   (not complete-coverage)))
              (latest-end now))
         (dolist (placement (plist-get forecast :placements))
           (when (and (equal (plist-get placement :project-key) key)
                      (time-less-p latest-end (plist-get placement :end)))
             (setq latest-end (plist-get placement :end))))
         (plist-put summary :graph-problems graph-problems)
         (plist-put
          summary :tightness
          (if unknown-p
              'unknown
            (floor
             (/ (float-time
                 (time-subtract
                  (my/lifeos--end-of-date (my/lifeos--deadline-date deadline))
                  latest-end))
                60))))))
     summaries)
    summaries))

(defun my/lifeos--project-summary-label-string (summary)
  "Return the compact transient indicator for SUMMARY."
  (let ((tightness (plist-get summary :tightness)))
    (format
     " [DONE %d/%d] [LEFT %s%s] [FIXED %d/%d] [PLAN %d/%d] [UNPLACED %d] [TIGHTNESS %s] "
     (plist-get summary :done-count)
     (plist-get summary :total-count)
     (my/lifeos--format-minutes (plist-get summary :left-minutes))
     (if-let* ((unknown (length (plist-get summary :unknown-records)))
               ((> unknown 0)))
         (format " +%d unknown" unknown)
       "")
     (plist-get summary :fixed-count)
     (plist-get summary :active-count)
     (plist-get summary :planned-count)
     (plist-get summary :active-count)
     (plist-get summary :unplaced-count)
     (cond
      ((eq tightness 'unknown) "unknown")
      ((< tightness 0) (format "LATE %s" (my/lifeos--format-minutes (- tightness))))
      (t (my/lifeos--format-minutes tightness))))))

(defun my/lifeos--record-titles (records)
  "Return a comma-separated title list for RECORDS."
  (if records
      (mapconcat (lambda (record) (or (plist-get record :title) "Unknown"))
                 (reverse records) ", ")
    "None"))

(defun my/lifeos--format-project-explanation (summary)
  "Return detailed metric definitions and affected work for SUMMARY."
  (format
   (concat "%s\n\n"
           "DONE: %d of %d non-cancelled executable descendants are complete.\n"
           "LEFT: %s of known positive estimate balance; unknown duration: %s.\n"
           "FIXED: %d of %d valid active tasks have committed timed SCHEDULED starts: %s.\n"
           "PLAN: %d of %d valid active tasks have fixed or read-only forecast placement: %s.\n"
           "UNPLACED: %d valid active tasks could not be placed: %s.\n"
           "TIGHTNESS: %s; this is forecast completion slack against the project deadline and is unknown when data, graph, duration, or placement is unresolved.\n"
           "Invalid metadata: %s.\n"
           "Graph problems: %s.\n")
   (plist-get summary :project-title)
   (plist-get summary :done-count) (plist-get summary :total-count)
   (my/lifeos--format-minutes (plist-get summary :left-minutes))
   (my/lifeos--record-titles (plist-get summary :unknown-records))
   (plist-get summary :fixed-count) (plist-get summary :active-count)
   (my/lifeos--record-titles (plist-get summary :fixed-records))
   (plist-get summary :planned-count) (plist-get summary :active-count)
   (my/lifeos--record-titles (plist-get summary :planned-records))
   (plist-get summary :unplaced-count)
   (my/lifeos--record-titles (plist-get summary :unplaced-failures))
   (let ((tightness (plist-get summary :tightness)))
     (cond ((eq tightness 'unknown) "unknown")
           ((< tightness 0)
            (format "late by %s" (my/lifeos--format-minutes (- tightness))))
           (t (my/lifeos--format-minutes tightness))))
   (my/lifeos--record-titles (plist-get summary :invalid-records))
   (if-let* ((problems (plist-get summary :graph-problems)))
       (mapconcat (lambda (problem) (format "%s" problem)) problems "; ")
     "None")))

(defun my/lifeos--forecast-task-diagnostics (forecast)
  "Return task-ID keyed diagnostics derived from FORECAST failures."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (failure (plist-get forecast :failures))
      (when-let* ((id (plist-get failure :id))
                  (code (plist-get failure :code))
                  ((not (eq code 'estimate-exhausted))))
        (push (my/lifeos--diagnostic
               code (or (plist-get failure :severity) 'conflict)
               (plist-get failure :reason) (plist-get failure :data))
              (gethash id table))))
    table))

(defun my/lifeos--current-week-start ()
  "Return the local Monday date for the current week."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (day (string-to-number (format-time-string "%w")))
         (offset (if (zerop day) 6 (1- day))))
    (my/lifeos--date-add-days today (- offset))))

(defun my/lifeos-refresh-project-analysis ()
  "Rebuild one shared graph, forecast, and project-summary snapshot."
  (interactive)
  (setq my/lifeos-project-analysis-timer nil)
  (condition-case error-data
      (let* ((analysis (my/lifeos-graph-analysis))
             (forecast (if (fboundp 'my/lifeos-build-forecast)
                           (my/lifeos-build-forecast
                            (my/lifeos--current-week-start) 4 analysis)
                         (list :placements nil :failures nil)))
             (summaries (my/lifeos--project-summaries analysis forecast)))
        (setq my/lifeos-project-analysis-cache
              (list :analysis analysis :forecast forecast :summaries summaries
                    :task-diagnostics
                    (my/lifeos--forecast-task-diagnostics forecast)
                    :built-at (current-time))
               my/lifeos-project-analysis-stale nil)
        (when (fboundp 'my/lifeos-solver-request-shadow)
          (condition-case solver-error
              (my/lifeos-solver-request-shadow analysis)
            (error
             (when (boundp 'my/lifeos-solver-last-error)
               (setq my/lifeos-solver-last-error
                     (error-message-string solver-error)))
             (message "LifeOS solver shadow failed: %s"
                      (error-message-string solver-error)))))
        (dolist (buffer (buffer-list))
          (with-current-buffer buffer
            (when (and (derived-mode-p 'org-mode)
                       my/lifeos-diagnostics-mode)
              (my/lifeos-refresh-buffer-diagnostics))))
        my/lifeos-project-analysis-cache)
    (error
     (setq my/lifeos-project-analysis-stale t)
     (message "LifeOS project analysis failed: %s"
              (error-message-string error-data))
     my/lifeos-project-analysis-cache)))

(defun my/lifeos-invalidate-project-analysis (&rest _)
  "Mark shared project analysis stale and schedule one idle rebuild."
  (setq my/lifeos-project-analysis-stale t)
  (when (timerp my/lifeos-project-analysis-timer)
    (cancel-timer my/lifeos-project-analysis-timer))
  (setq my/lifeos-project-analysis-timer
        (run-with-idle-timer my/lifeos-project-analysis-idle-delay nil
                             #'my/lifeos-refresh-project-analysis)))

(defun my/lifeos--cached-project-summary-at-point ()
  "Return the cached summary for the #project at point."
  (when (and my/lifeos-project-analysis-cache
             (my/lifeos--heading-has-supertag-p "project"))
    (gethash (my/lifeos--heading-key)
             (plist-get my/lifeos-project-analysis-cache :summaries))))

(defun my/lifeos-explain-at-point ()
  "Explain LifeOS task or project findings and available metrics at point."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "LifeOS explanation requires an Org buffer"))
  (org-back-to-heading t)
  (let ((text
         (cond
           ((my/lifeos--heading-has-supertag-p "project")
            (let* ((project (my/lifeos-project-record-at-point))
                   (diagnostics (plist-get project :diagnostics))
                   (summary (my/lifeos--cached-project-summary-at-point)))
              (concat
               (my/lifeos--format-task-explanation
                (plist-get project :title) diagnostics)
               "\nForecast metrics\n\n"
               (if summary
                   (my/lifeos--format-project-explanation summary)
                 "No cached forecast metrics are available yet.\n"))))
          ((or (my/lifeos--heading-has-supertag-p "task")
               (org-get-todo-state))
           (my/lifeos--format-task-explanation
             (org-get-heading t t t t) (my/lifeos--task-diagnostics-at-point)))
          (t (user-error "Point is not on a LifeOS task or project")))))
    (with-help-window "*LifeOS Explain*"
      (princ text))))

(provide 'lifeos-planning)
