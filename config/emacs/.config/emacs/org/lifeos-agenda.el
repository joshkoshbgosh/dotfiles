;; -*- lexical-binding: t -*-
;;; org/lifeos-agenda.el --- Unified LifeOS agenda dashboard

;;; Commentary:

;; Extends a native one-day Org agenda with bounded action, exception, planning
;; status, and project blocks.  Source-backed rows retain Org markers so native
;; agenda navigation and Embark heading actions continue to work.

;;; Code:

(require 'org-agenda)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'lifeos-planning)
(require 'lifeos-forecast)
(require 'lifeos-schedule)
(require 'lifeos-solver)

(defcustom my/lifeos-agenda-ready-limit 5
  "Maximum number of ready tasks shown in the LifeOS agenda."
  :type 'integer
  :group 'my/lifeos)

(defcustom my/lifeos-agenda-attention-limit 5
  "Maximum number of task exceptions shown in the LifeOS agenda."
  :type 'integer
  :group 'my/lifeos)

(defface my/lifeos-agenda-good
  '((t :inherit success))
  "Face for healthy LifeOS agenda status."
  :group 'my/lifeos)

(defface my/lifeos-agenda-warning
  '((t :inherit warning))
  "Face for LifeOS agenda status needing attention."
  :group 'my/lifeos)

(defface my/lifeos-agenda-error
  '((t :inherit error))
  "Face for invalid or infeasible LifeOS agenda status."
  :group 'my/lifeos)

(defface my/lifeos-agenda-muted
  '((t :inherit shadow))
  "Face for inactive LifeOS agenda status."
  :group 'my/lifeos)

(defvar-local my/lifeos-agenda--snapshot nil
  "Local analysis snapshot used while rendering the current agenda.")

(defun my/lifeos-agenda--build-local-snapshot ()
  "Build local dashboard data without starting solver or calendar work."
  (let* ((analysis (my/lifeos-graph-analysis))
         (forecast (if (fboundp 'my/lifeos-build-forecast)
                       (my/lifeos-build-forecast
                        (my/lifeos--current-week-start) 4 analysis)
                     (list :placements nil :failures nil)))
         (summaries (my/lifeos--project-summaries analysis forecast)))
    (list :analysis analysis :forecast forecast :summaries summaries
          :task-diagnostics (my/lifeos--forecast-task-diagnostics forecast)
          :built-at (current-time) :dashboard-local t)))

(defun my/lifeos-agenda--refresh-snapshot ()
  "Select current local data for one dashboard rendering pass."
  (setq-local my/lifeos-agenda--snapshot
              (if (and my/lifeos-project-analysis-cache
                       (not my/lifeos-project-analysis-stale))
                  my/lifeos-project-analysis-cache
                (my/lifeos-agenda--build-local-snapshot))))

(defun my/lifeos-agenda--analysis ()
  "Return the analysis displayed by the current dashboard."
  (plist-get (or my/lifeos-agenda--snapshot
                 (my/lifeos-agenda--refresh-snapshot))
             :analysis))

(defun my/lifeos-agenda--insert-header (title)
  "Insert a dashboard section header named TITLE."
  (insert (propertize title 'face 'org-agenda-structure) "\n"))

(defun my/lifeos-agenda--insert-empty (text)
  "Insert muted empty-state TEXT."
  (insert (propertize (concat "  " text "\n")
                      'face 'my/lifeos-agenda-muted)))

(defun my/lifeos-agenda--insert-heading-row (text marker &optional face properties)
  "Insert agenda row TEXT linked to MARKER with FACE and PROPERTIES."
  (let ((start (point)))
    (insert "  " text "\n")
    (when (and (markerp marker) (marker-buffer marker))
      (add-text-properties
       start (point)
       (list 'org-marker marker 'org-hd-marker marker
             'mouse-face 'highlight 'rear-nonsticky t)))
    (when face
      (add-face-text-property start (1- (point)) face nil))
    (when properties
      (add-text-properties start (point) properties))))

(defun my/lifeos-agenda--record-deadline-date (record)
  "Return RECORD's deadline date, sorting missing dates last."
  (let ((deadline (plist-get record :deadline)))
    (if (and deadline
             (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" deadline))
        (match-string 0 deadline)
      "9999-99-99")))

(defun my/lifeos-agenda--record-rank (record)
  "Return a decision-oriented sort rank for task RECORD."
  (list (my/lifeos-agenda--record-deadline-date record)
        (or (cl-position (plist-get record :priority)
                         '("A" "B" "C" "D") :test #'equal)
            9)
        (or (cl-position (plist-get record :impact)
                         '("High" "Medium" "Low") :test #'equal)
            9)
        (or (plist-get record :minutes) most-positive-fixnum)
        (or (plist-get record :title) "")))

(defun my/lifeos-agenda--rank-less-p (left right)
  "Return non-nil when rank list LEFT sorts before RIGHT."
  (catch 'different
    (while left
      (let ((a (pop left)) (b (pop right)))
        (unless (equal a b)
          (throw 'different
                 (if (and (numberp a) (numberp b)) (< a b)
                   (string< (format "%s" a) (format "%s" b)))))))
    nil))

(defun my/lifeos-agenda--sort-records (records)
  "Return task RECORDS in dashboard decision order."
  (sort (copy-sequence records)
        (lambda (left right)
          (my/lifeos-agenda--rank-less-p
           (my/lifeos-agenda--record-rank left)
           (my/lifeos-agenda--record-rank right)))))

(defun my/lifeos-agenda--task-detail (record)
  "Return compact decision metadata for task RECORD."
  (string-join
   (delq nil
         (list (when-let* ((minutes (plist-get record :minutes)))
                 (my/lifeos--format-minutes minutes))
               (plist-get record :work-mode)
               (when-let* ((deadline (plist-get record :deadline)))
                 (concat "due " (my/lifeos--deadline-date deadline)))))
   "  "))

(defun my/lifeos-agenda--task-row (record &optional label face)
  "Insert task RECORD with optional LABEL and FACE."
  (let ((detail (my/lifeos-agenda--task-detail record)))
    (my/lifeos-agenda--insert-heading-row
     (format "%s%-7s %s%s"
             (if label (format "%-9s " label) "")
             (or (plist-get record :state) "")
             (or (plist-get record :title) "Untitled")
             (if (string-empty-p detail) "" (concat "    " detail)))
     (plist-get record :marker) face)))

(defun my/lifeos-agenda-ready (_match)
  "Insert a bounded list of valid, unblocked executable work."
  (my/lifeos-agenda--refresh-snapshot)
  (let* ((inhibit-read-only t)
         (analysis (my/lifeos-agenda--analysis))
         (edges (plist-get analysis :edges))
         (records
          (seq-filter
           (lambda (record)
             (and (plist-get record :eligible)
                  (plist-get record :executable)
                  (member (plist-get record :state) '("TODO" "NEXT"))
                  (null (alist-get (plist-get record :id) edges nil nil #'equal))))
           (plist-get analysis :all-records)))
         (sorted (my/lifeos-agenda--sort-records records))
         (shown (seq-take sorted my/lifeos-agenda-ready-limit)))
    (my/lifeos-agenda--insert-header "Next actions")
    (if shown
        (dolist (record shown) (my/lifeos-agenda--task-row record))
      (my/lifeos-agenda--insert-empty "No valid ready tasks."))
    (when (> (length sorted) (length shown))
      (my/lifeos-agenda--insert-empty
       (format "%d more ready tasks hidden." (- (length sorted) (length shown)))))
    (insert "\n")))

(defun my/lifeos-agenda--attention-records (analysis)
  "Return task records from ANALYSIS that need intervention."
  (let ((edges (plist-get analysis :edges)))
    (seq-filter
     (lambda (record)
       (and (member (plist-get record :state) '("TODO" "NEXT" "WAITING"))
            (or (not (plist-get record :eligible))
                (equal (plist-get record :state) "WAITING")
                (alist-get (plist-get record :id) edges nil nil #'equal))))
     (plist-get analysis :all-records))))

(defun my/lifeos-agenda--attention-label (record analysis)
  "Return the exception label for RECORD in ANALYSIS."
  (cond
   ((not (plist-get record :eligible)) "GROOM")
   ((equal (plist-get record :state) "WAITING") "WAITING")
   ((alist-get (plist-get record :id) (plist-get analysis :edges)
               nil nil #'equal)
    "BLOCKED")
   (t "CHECK")))

(defun my/lifeos-agenda-attention (_match)
  "Insert a bounded exception-first task list."
  (let* ((inhibit-read-only t)
         (analysis (my/lifeos-agenda--analysis))
         (records (my/lifeos-agenda--sort-records
                   (my/lifeos-agenda--attention-records analysis)))
         (shown (seq-take records my/lifeos-agenda-attention-limit)))
    (my/lifeos-agenda--insert-header "Needs attention")
    (if shown
        (dolist (record shown)
          (my/lifeos-agenda--task-row
           record (my/lifeos-agenda--attention-label record analysis)
           (if (plist-get record :eligible)
               'my/lifeos-agenda-warning 'my/lifeos-agenda-error)))
      (my/lifeos-agenda--insert-empty "No task exceptions."))
    (when (> (length records) (length shown))
      (let ((start (point)))
        (my/lifeos-agenda--insert-empty
         (format "%d more exceptions hidden; use C-. here for actions."
                 (- (length records) (length shown))))
        (add-text-properties
         start (point)
         (list 'lifeos-agenda-target 'status 'mouse-face 'highlight
               'rear-nonsticky t))))
    (insert "\n")))

(defun my/lifeos-agenda--routine-records (period)
  "Return active routine headings for day-part PERIOD."
  (let ((file (expand-file-name "routines.org" org-directory))
        records)
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-map-entries
          (lambda ()
            (when (and (member (org-get-todo-state) '("TODO" "NEXT"))
                       (member "routine" (org-get-tags nil nil))
                       (member period (org-get-tags nil nil)))
              (push (list :title (org-get-heading t t t t)
                          :state (org-get-todo-state)
                          :marker (copy-marker (point)))
                    records)))
          nil 'file))))
    (nreverse records)))

(defun my/lifeos-agenda-routines (_match)
  "Insert compact morning, afternoon, and evening routine blocks."
  (let ((inhibit-read-only t))
    (dolist (period '("morning" "afternoon" "evening"))
      (let ((records (my/lifeos-agenda--routine-records period)))
        (my/lifeos-agenda--insert-header
         (format "%s routine" (capitalize period)))
        (if records
            (dolist (record records)
              (my/lifeos-agenda--insert-heading-row
               (format "%-7s %s" (plist-get record :state)
                       (plist-get record :title))
               (plist-get record :marker)))
          (my/lifeos-agenda--insert-empty "No remaining routine items."))
        (insert "\n")))))

(defun my/lifeos-agenda--solver-pair (analysis)
  "Return solver result and context suitable for dashboard ANALYSIS."
  (let ((running-context
         (and (processp my/lifeos-solver-process)
              (process-live-p my/lifeos-solver-process)
              (process-get my/lifeos-solver-process 'lifeos-context))))
    (cons my/lifeos-solver-last-good-result
          (or running-context
              my/lifeos-solver-last-good-request-context
              (list :analysis analysis :request nil)))))

(defun my/lifeos-agenda--calendar-status ()
  "Return a compact calendar freshness label."
  (cond
   ((eq (bound-and-true-p my/org-gcal-last-poll-error)
        'authentication-required)
    "AUTH REQUIRED")
   ((and (boundp 'my/org-gcal-fetch-in-progress)
         my/org-gcal-fetch-in-progress)
    "FETCHING")
   ((not (bound-and-true-p my/org-gcal-last-successful-fetch-time))
    "UNKNOWN")
   ((> (/ (float-time
            (time-subtract (current-time)
                           my/org-gcal-last-successful-fetch-time))
          60)
       (if (boundp 'my/lifeos-solver-calendar-coverage-max-age-minutes)
           my/lifeos-solver-calendar-coverage-max-age-minutes 30))
    "STALE")
   (t "CURRENT")))

(defun my/lifeos-agenda--status-face (status)
  "Return a face appropriate for planning STATUS."
  (pcase status
    ("FITS" 'my/lifeos-agenda-good)
    ("AT RISK" 'my/lifeos-agenda-warning)
    ("DOES NOT FIT" 'my/lifeos-agenda-error)
    (_ 'my/lifeos-agenda-warning)))

(defun my/lifeos-agenda-status (_match)
  "Insert compact general planning and freshness values."
  (let* ((inhibit-read-only t)
         (analysis (my/lifeos-agenda--analysis))
         (pair (my/lifeos-agenda--solver-pair analysis))
         (result (car pair))
         (context (cdr pair))
         (evidence (my/lifeos-solver--portfolio-evidence-state result context))
         (planning (my/lifeos-schedule-portfolio-status result context))
         (needs-info
          (length (plist-get (plist-get my/lifeos-agenda--snapshot :forecast)
                             :data-errors)))
         (incomplete-projects
          (seq-count (lambda (project)
                       (eq (plist-get project :definition-status) 'incomplete))
                     (plist-get analysis :projects)))
         (unplaced
          (seq-reduce
           (lambda (total summary)
             (+ total (or (plist-get summary :unplaced-count) 0)))
           (let (values)
             (maphash (lambda (_key value) (push value values))
                      (plist-get my/lifeos-agenda--snapshot :summaries))
             values)
           0))
         (line (format "  Planning: %s    Evidence: %s    Calendar: %s\n"
                       planning evidence (my/lifeos-agenda--calendar-status)))
         (details (format "  Needs info: %d headings, %d projects    Unplaced: %d    C-. actions\n"
                          needs-info incomplete-projects unplaced)))
    (my/lifeos-agenda--insert-header "LifeOS status")
    (let ((start (point)))
      (insert line details)
      (add-text-properties
       start (point)
       (list 'lifeos-agenda-target 'status 'mouse-face 'highlight
             'rear-nonsticky t))
      (add-face-text-property start (+ start (length line) -1)
                              (my/lifeos-agenda--status-face planning) nil))
    (insert "\n")))

(defun my/lifeos-agenda--project-result (portfolio project)
  "Return current PORTFOLIO evidence for PROJECT."
  (when-let* ((id (plist-get project :id)))
    (my/lifeos-solver--project-result portfolio id)))

(defun my/lifeos-agenda--project-display-status (project summary result evidence)
  "Return compact status for PROJECT, SUMMARY, RESULT, and EVIDENCE."
  (cond
   ((eq (plist-get project :commitment) 'uncommitted) "INACTIVE")
   ((eq (plist-get project :definition-status) 'incomplete) "NEED INFO")
   ((or (> (or (plist-get summary :unplaced-count) 0) 0)
        (and (numberp (plist-get summary :tightness))
             (< (plist-get summary :tightness) 0)))
    "AT RISK")
   ((and (equal evidence "CURRENT") result)
    (pcase (alist-get 'portfolioStatus result)
      ("FITS" "FITS")
      ("TIGHT" "AT RISK")
      ("CONFLICT-INVOLVED" "AT RISK")
      ("UNCOMMITTED" "INACTIVE")
      (_ "NEED INFO")))
   (t "LOCAL")))

(defun my/lifeos-agenda--project-finding (project summary result)
  "Return one actionable finding for PROJECT using SUMMARY and RESULT."
  (or (plist-get (car (plist-get project :diagnostics)) :message)
      (when (> (or (plist-get summary :unplaced-count) 0) 0)
        (format "%d unplaced" (plist-get summary :unplaced-count)))
      (when (> (length (plist-get summary :unknown-records)) 0)
        (format "%d unknown estimates"
                (length (plist-get summary :unknown-records))))
      (and result
           (equal (alist-get 'portfolioStatus result) "CONFLICT-INVOLVED")
           "portfolio conflict")
      (when (eq (plist-get project :commitment) 'uncommitted)
        (downcase (or (plist-get project :state) "uncommitted")))
      (downcase (symbol-name (plist-get project :definition-status)))))

(defun my/lifeos-agenda--project-group (status)
  "Return the dashboard group for project STATUS."
  (cond ((member status '("AT RISK" "NEED INFO")) 'attention)
        ((equal status "INACTIVE") 'inactive)
        (t 'track)))

(defun my/lifeos-agenda--project-face (status)
  "Return a face for project STATUS."
  (pcase status
    ("FITS" 'my/lifeos-agenda-good)
    ("LOCAL" 'default)
    ("INACTIVE" 'my/lifeos-agenda-muted)
    ("AT RISK" 'my/lifeos-agenda-warning)
    (_ 'my/lifeos-agenda-error)))

(defun my/lifeos-agenda--project-row (item)
  "Insert one compact project ITEM."
  (let* ((project (plist-get item :project))
         (summary (plist-get item :summary))
         (result (plist-get item :result))
         (status (plist-get item :status))
         (deadline-date (my/lifeos--deadline-date (plist-get project :deadline)))
         (deadline (if (string-empty-p deadline-date) "none" deadline-date))
         (remaining (or (plist-get project :remaining-effort-minutes)
                        (when (> (or (plist-get summary :left-minutes) 0) 0)
                          (plist-get summary :left-minutes)))))
    (my/lifeos-agenda--insert-heading-row
     (format "%-10s %-32s  due %-10s  left %-6s  %s"
             status
             (truncate-string-to-width
              (or (plist-get project :title) "Untitled") 32 nil nil "...")
             deadline
             (if (numberp remaining)
                 (my/lifeos--format-minutes remaining) "unknown")
             (truncate-string-to-width
              (my/lifeos-agenda--project-finding project summary result)
              48 nil nil "..."))
     (plist-get project :marker) (my/lifeos-agenda--project-face status)
     (list 'lifeos-project-id (plist-get project :id)))))

(defun my/lifeos-agenda--project-sort-p (left right)
  "Return non-nil when project item LEFT sorts before RIGHT."
  (let* ((a (plist-get left :project)) (b (plist-get right :project))
         (ad (or (my/lifeos--deadline-date (plist-get a :deadline)) "9999-99-99"))
         (bd (or (my/lifeos--deadline-date (plist-get b :deadline)) "9999-99-99")))
    (if (equal ad bd)
        (string< (or (plist-get a :title) "") (or (plist-get b :title) ""))
      (string< ad bd))))

(defun my/lifeos-agenda-projects (_match)
  "Insert every project, grouped by computed attention state."
  (let* ((inhibit-read-only t)
         (analysis (my/lifeos-agenda--analysis))
         (pair (my/lifeos-agenda--solver-pair analysis))
         (result (car pair)) (context (cdr pair))
         (evidence (my/lifeos-solver--portfolio-evidence-state result context))
         (portfolio (and result (alist-get 'baselinePortfolio result)))
         (summaries (plist-get my/lifeos-agenda--snapshot :summaries))
         groups)
    (dolist (project (plist-get analysis :projects))
      (let* ((summary (or (gethash (plist-get project :key) summaries)
                          (list :unplaced-count 0 :unknown-records nil)))
             (project-result (and (equal evidence "CURRENT")
                                  (my/lifeos-agenda--project-result portfolio project)))
             (status (my/lifeos-agenda--project-display-status
                      project summary project-result evidence))
             (item (list :project project :summary summary
                         :result project-result :status status)))
        (push item (alist-get (my/lifeos-agenda--project-group status) groups))))
    (dolist (group '((attention . "Projects needing attention")
                     (track . "Projects on track")
                     (inactive . "Inactive / uncommitted projects")))
      (my/lifeos-agenda--insert-header (cdr group))
      (if-let* ((items (sort (alist-get (car group) groups)
                             #'my/lifeos-agenda--project-sort-p)))
          (dolist (item items) (my/lifeos-agenda--project-row item))
        (my/lifeos-agenda--insert-empty "None."))
      (insert "\n"))))

(defun my/lifeos-agenda--append-dashboard ()
  "Append computed LifeOS sections after native agenda finalization."
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "\n")
      (my/lifeos-agenda-routines "")
      (my/lifeos-agenda-ready "")
      (my/lifeos-agenda-attention "")
      (my/lifeos-agenda-status "")
      (my/lifeos-agenda-projects ""))))

(defun my/lifeos-agenda ()
  "Open the unified LifeOS dashboard in Org Agenda."
  (interactive)
  (org-agenda nil "d"))

(defun my/lifeos-agenda-refresh ()
  "Refresh local and solver analysis, then redraw the agenda."
  (interactive)
  (my/lifeos-refresh-project-analysis)
  (when (derived-mode-p 'org-agenda-mode)
    (org-agenda-redo)))

(defun my/lifeos-agenda-fetch-calendar ()
  "Start a calendar fetch from a LifeOS agenda status target."
  (interactive)
  (if (fboundp 'my/org-gcal-fetch)
      (call-interactively #'my/org-gcal-fetch)
    (user-error "Calendar integration is not loaded")))

(defun my/lifeos-agenda-groom-at-point ()
  "Groom the LifeOS task or project selected by Embark."
  (interactive)
  (cond ((my/lifeos--heading-has-supertag-p "project")
         (call-interactively #'my/lifeos-groom-project))
        ((my/lifeos--heading-has-supertag-p "task")
         (call-interactively #'my/lifeos-groom-task))
        (t (user-error "This heading is not a LifeOS task or project"))))

(defun my/lifeos-agenda--embark-target ()
  "Return a typed Embark target for LifeOS status text at point."
  (when (and (derived-mode-p 'org-agenda-mode)
             (get-text-property (line-beginning-position)
                                'lifeos-agenda-target))
    (let ((start (line-beginning-position)) (end (line-end-position)))
      `(lifeos-status ,(buffer-substring start end) ,start . ,end))))

(with-eval-after-load 'embark-org
  (defvar-keymap my/lifeos-embark-status-map
    :doc "Actions for computed LifeOS agenda status."
    :parent embark-general-map
    "RET" #'my/lifeos-solver-show-portfolio-review
    "p" #'my/lifeos-solver-show-portfolio-review
    "r" #'my/lifeos-agenda-refresh
    "c" #'my/lifeos-agenda-fetch-calendar
    "g" (lambda () (interactive) (my/lifeos-needs-grooming 'due-soon)))
  (add-to-list 'embark-keymap-alist '(lifeos-status my/lifeos-embark-status-map))
  (add-to-list 'embark-target-finders #'my/lifeos-agenda--embark-target)
  (define-key embark-org-heading-map (kbd "e") #'my/lifeos-explain-at-point)
  (define-key embark-org-heading-map (kbd "g") #'my/lifeos-agenda-groom-at-point)
  (dolist (command '(my/lifeos-explain-at-point my/lifeos-agenda-groom-at-point))
    (cl-pushnew 'embark-org-goto-heading
                (alist-get command embark-pre-action-hooks))))

(with-eval-after-load 'org-agenda
  (add-to-list
   'org-agenda-custom-commands
   '("d" "LifeOS dashboard" agenda ""
     ((org-agenda-overriding-header "Today")
      (org-agenda-span 1)
      (org-agenda-start-day nil)
      (org-agenda-start-on-weekday nil)
      (org-agenda-show-all-dates nil)
      (org-agenda-use-time-grid t)
      (org-agenda-skip-scheduled-if-done t)
      (org-agenda-skip-deadline-if-done t)
      (org-agenda-finalize-hook
       (append org-agenda-finalize-hook
               '(my/lifeos-agenda--append-dashboard)))
      (org-super-agenda-groups
       '((:discard (:file-path "routines\\.org"))
         (:name "Habits" :file-path "habits\\.org")
         (:name "Calendar" :file-path "calendar\\.org")
         (:name "Timed commitments" :time-grid t)
         (:name "Deadlines" :deadline t)
         (:name "Other today" :anything t)))))))

(provide 'lifeos-agenda)

;;; lifeos-agenda.el ends here
