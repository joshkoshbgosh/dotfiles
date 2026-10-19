;; -*- lexical-binding: t -*-
;;; org/lifeos-solver.el --- Async LifeOS Z3 shadow planning

(require 'json)
(require 'button)
(require 'lifeos-planning)
(require 'lifeos-forecast)
(require 'lifeos-schedule)
(require 'seq)
(require 'subr-x)

(defconst my/lifeos-solver-protocol-version "lifeos-planning/v3")
(defconst my/lifeos-solver-version "lifeos-z3/0.3.0+z3-solver/5.2.0")
(defconst my/lifeos-solver-module-file
  (or load-file-name buffer-file-name)
  "Absolute source path captured while loading the LifeOS solver module.")

(defcustom my/lifeos-solver-shadow-enabled t
  "When non-nil, solve normalized planning data after heuristic refreshes."
  :type 'boolean
  :group 'my/lifeos)

(defcustom my/lifeos-solver-timeout-milliseconds 5000
  "Z3 timeout for each feasibility or optimization stage."
  :type 'integer
  :group 'my/lifeos)

(defcustom my/lifeos-solver-calendar-coverage-max-age-minutes 30
  "Maximum age of a successful calendar fetch used as coverage evidence."
  :type 'integer
  :group 'my/lifeos)

(defcustom my/lifeos-solver-default-safety-buffer-minutes (* 24 60)
  "Default deadline safety buffer, conservatively 24 hours.
An explicit nil remains an unconfigured user override."
  :type '(choice (const :tag "Unconfigured" nil) integer)
  :group 'my/lifeos)

(defcustom my/lifeos-solver-sleep
  '(:earliest-start "22:00" :latest-end "09:00" :minimum-minutes 480)
  "Nightly sleep plist with :earliest-start, :latest-end, and :minimum-minutes.
Nil means mandatory sleep configuration is incomplete."
  :type '(choice (const :tag "Unconfigured" nil) plist)
  :group 'my/lifeos)

(defcustom my/lifeos-solver-daily-reserve-minutes 60
  "Daily reserve minutes, or nil while unconfigured."
  :type '(choice (const :tag "Unconfigured" nil) integer)
  :group 'my/lifeos)

(defcustom my/lifeos-solver-weekly-reserve-minutes 240
  "Weekly reserve minutes, or nil while unconfigured."
  :type '(choice (const :tag "Unconfigured" nil) integer)
  :group 'my/lifeos)

(defcustom my/lifeos-solver-reserve-block-minutes 60
  "Minimum contiguous reserve block, or nil while unconfigured."
  :type '(choice (const :tag "Unconfigured" nil) integer)
  :group 'my/lifeos)

(defcustom my/lifeos-solver-travel-defaults '(("default" . (45 . 45)))
  "Alist mapping normalized event types to (BEFORE . AFTER) travel minutes."
  :type '(alist :key-type string :value-type (cons integer integer))
  :group 'my/lifeos)

(defcustom my/lifeos-solver-unknown-travel-default '(60 . 60)
  "Conservative (BEFORE . AFTER) travel minutes for unknown event types."
  :type '(choice (const :tag "Unconfigured" nil) (cons integer integer))
  :group 'my/lifeos)

(defcustom my/lifeos-solver-remote-setup-minutes 15
  "Setup time immediately before a remote calendar event."
  :type '(choice (const :tag "Unconfigured" nil) integer)
  :group 'my/lifeos)

(defcustom my/lifeos-solver-stress-estimate-overrun-enabled nil
  "When non-nil, generate the estimate-overrun stress profile."
  :type 'boolean
  :group 'my/lifeos)

(defcustom my/lifeos-solver-stress-estimate-overrun-percent nil
  "Percentage added to known remaining estimates in the stress profile."
  :type '(choice (const :tag "Unconfigured" nil) integer)
  :group 'my/lifeos)

(defcustom my/lifeos-solver-stress-lose-largest-deep-window-enabled nil
  "When non-nil, generate a stress profile removing the largest Deep window."
  :type 'boolean
  :group 'my/lifeos)

(defcustom my/lifeos-solver-stress-unexpected-appointment-enabled nil
  "When non-nil, generate an unexpected-appointment stress profile."
  :type 'boolean
  :group 'my/lifeos)

(defcustom my/lifeos-solver-stress-unexpected-appointment-minutes nil
  "Duration of the unexpected-appointment stress reservation."
  :type '(choice (const :tag "Unconfigured" nil) integer)
  :group 'my/lifeos)

(defvar my/org-gcal-last-successful-fetch-time nil)
(defvar my/org-gcal-calendar-coverage-end nil)

(defcustom my/lifeos-solver-command nil
  "Command list used to invoke the LifeOS solver.
Nil derives an npm command from the dotfiles repository."
  :type '(repeat string)
  :group 'my/lifeos)

(defvar my/lifeos-solver-process nil)
(defvar my/lifeos-solver-process-timer nil)
(defvar my/lifeos-solver-request-sequence 0)
(defvar my/lifeos-solver-current-request-id nil)
(defvar my/lifeos-solver-last-good-result nil
  "Last successful, non-stale solver response.")
(defvar my/lifeos-solver-last-good-json nil
  "Raw JSON for `my/lifeos-solver-last-good-result'.")
(defvar my/lifeos-solver-last-error nil)
(defvar my/lifeos-solver-source-markers (make-hash-table :test #'equal)
  "Source IDs mapped to Org markers from the last accepted response.")
(defvar my/lifeos-solver-last-request-context nil
  "Request context for the most recently completed current solver attempt.")
(defvar my/lifeos-solver-last-good-request-context nil
  "Request context paired with the last accepted solver response.")
(defvar my/lifeos-solver-current-scenario nil
  "Current ephemeral scenario assembled by interactive scenario commands.")

(defvar-local my/lifeos-portfolio-review-context nil
  "Snapshot context displayed by the current Portfolio Review buffer.")
(defvar-local my/lifeos-portfolio-review-result nil
  "Solver result displayed by the current Portfolio Review buffer.")

(defconst my/lifeos-solver--active-states '("TODO" "NEXT" "WAITING"))

(defun my/lifeos-solver--minute (time)
  "Return integer epoch minutes for TIME."
  (floor (/ (float-time time) 60)))

(defun my/lifeos-solver--quantum-at-or-after (time)
  "Return the first 15-minute epoch quantum at or after TIME."
  (let ((minute (/ (float-time time) 60.0)))
    (* 15 (ceiling (/ minute 15.0)))))

(defun my/lifeos-solver--active-record-p (record)
  "Return non-nil when RECORD is in an active planning state."
  (member (plist-get record :state) my/lifeos-solver--active-states))

(defun my/lifeos-solver--mandatory-record-p (record)
  "Return non-nil when RECORD has a deadline or fixed start."
  (or (plist-get record :deadline)
      (my/lifeos--record-scheduled-time record)))

(defun my/lifeos-solver--solver-valid-p (record)
  "Return non-nil when RECORD has the structure required by the solver."
  (and (plist-get record :id)
       (plist-get record :executable)
       (my/lifeos-solver--active-record-p record)
       (not (seq-some
             (lambda (diagnostic)
               (eq (plist-get diagnostic :severity) 'error))
             (plist-get record :diagnostics)))))

(defun my/lifeos-solver--record-table (records)
  "Return RECORDS indexed by ID."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (record records table)
      (when-let* ((id (plist-get record :id)))
        (puthash id record table)))))

(defun my/lifeos-solver--mandatory-closure (records)
  "Return IDs in the mandatory dependency closure of RECORDS."
  (let ((by-id (my/lifeos-solver--record-table records))
        (mandatory (make-hash-table :test #'equal))
        pending)
    (dolist (record records)
      (when (and (my/lifeos-solver--active-record-p record)
                 (my/lifeos-solver--mandatory-record-p record))
        (let ((id (plist-get record :id)))
          (when id
            (puthash id t mandatory)
            (push id pending)))))
    (while pending
      (let ((record (gethash (pop pending) by-id)))
        (dolist (target (plist-get record :targets))
          (when-let* ((target-record (gethash target by-id))
                      ((my/lifeos-solver--active-record-p target-record))
                      ((not (gethash target mandatory))))
            (puthash target t mandatory)
            (push target pending)))))
    mandatory))

(defun my/lifeos-solver--same-source-p (left right)
  "Return non-nil when LEFT and RIGHT markers identify the same heading."
  (and (markerp left) (markerp right)
       (eq (marker-buffer left) (marker-buffer right))
       (= (marker-position left) (marker-position right))))

(defun my/lifeos-solver--ungroomed-mandatory-issues (records)
  "Return hard issues for mandatory ungroomed headings absent from RECORDS."
  (let ((record-markers (delq nil (mapcar (lambda (record)
                                            (plist-get record :marker))
                                          records)))
        issues)
    (dolist (grooming-record (my/lifeos--grooming-records 'all))
      (let ((marker (plist-get grooming-record :marker)))
        (when (and (member (plist-get grooming-record :todo)
                           my/lifeos-solver--active-states)
                   marker (marker-buffer marker)
                   (not (seq-some (lambda (record-marker)
                                    (my/lifeos-solver--same-source-p
                                     marker record-marker))
                                  record-markers)))
          (with-current-buffer (marker-buffer marker)
            (save-excursion
              (goto-char marker)
              (when (or (org-entry-get nil "DEADLINE")
                        (my/lifeos--timed-scheduled-time-at-point))
                (push (format "Active mandatory heading %s is ungroomed and absent from the task graph."
                              (my/lifeos-solver--source-id
                               (list :marker marker) "ungroomed-task"))
                      issues)))))))
    (nreverse issues)))

(defun my/lifeos-solver--source-id (record kind)
  "Return a non-secret source ID for RECORD of KIND."
  (or (plist-get record :id)
      (when-let* ((marker (plist-get record :marker)))
        (format "%s:%s:%d" kind
                (file-name-nondirectory
                 (or (buffer-file-name (marker-buffer marker)) "buffer"))
                (marker-position marker)))
      (format "%s:unknown" kind)))

(defun my/lifeos-solver--evidence (source-id kind &optional detail)
  "Build normalized evidence for SOURCE-ID, KIND, and optional DETAIL."
  (append `((sourceId . ,source-id) (kind . ,kind))
          (and detail `((detail . ,detail)))))

(defconst my/lifeos-solver--configuration-keys
  '("Sleep earliest start" "Sleep latest end" "Sleep minimum"
    "Default safety buffer" "Daily reserve" "Weekly reserve" "Reserve block"
    "Known travel default" "Unknown travel default" "Remote setup"
    "Stress estimate overrun enabled" "Stress estimate overrun percent"
    "Stress lose largest Deep window enabled"
    "Stress unexpected appointment enabled"
     "Stress unexpected appointment duration"))

(defconst my/lifeos-solver--configuration-template-rows
  '(("Key" "Value")
    ("Sleep earliest start" "22:00")
    ("Sleep latest end" "09:00")
    ("Sleep minimum" "8:00")
    ("Default safety buffer" "24:00")
    ("Daily reserve" "1:00")
    ("Weekly reserve" "4:00")
    ("Reserve block" "1:00")
    ("Known travel default" "0:45 / 0:45")
    ("Unknown travel default" "1:00 / 1:00")
    ("Remote setup" "0:15")
    ("Stress estimate overrun enabled" "no")
    ("Stress estimate overrun percent" "25")
    ("Stress lose largest Deep window enabled" "no")
    ("Stress unexpected appointment enabled" "no")
    ("Stress unexpected appointment duration" "1:00"))
  "Complete parser-valid Solver configuration template.")

(defconst my/lifeos-manual-file
  (expand-file-name "~/Work/lifeos/docs/lifeos/index.org")
  "User-facing LifeOS manual root outside the dotfiles repository.")

(defun my/lifeos-solver--configuration-defaults ()
  "Return solver settings from customizable fallback values."
  (list :sleep my/lifeos-solver-sleep
        :default-safety-buffer my/lifeos-solver-default-safety-buffer-minutes
        :daily-reserve my/lifeos-solver-daily-reserve-minutes
        :weekly-reserve my/lifeos-solver-weekly-reserve-minutes
        :reserve-block my/lifeos-solver-reserve-block-minutes
        :travel-defaults my/lifeos-solver-travel-defaults
        :unknown-travel my/lifeos-solver-unknown-travel-default
        :remote-setup my/lifeos-solver-remote-setup-minutes
        :stress-estimate-enabled my/lifeos-solver-stress-estimate-overrun-enabled
        :stress-estimate-percent my/lifeos-solver-stress-estimate-overrun-percent
        :stress-deep-enabled my/lifeos-solver-stress-lose-largest-deep-window-enabled
        :stress-appointment-enabled my/lifeos-solver-stress-unexpected-appointment-enabled
        :stress-appointment-minutes
        my/lifeos-solver-stress-unexpected-appointment-minutes))

(defun my/lifeos-solver--configuration-table (marker)
  "Return the Solver configuration table below MARKER, or nil when absent."
  (when marker
    (condition-case nil
        (my/lifeos--table-rows-under marker "Solver configuration")
      (error nil))))

(defun my/lifeos-solver--parse-clock (key value)
  "Parse strict 24-hour clock VALUE for KEY."
  (unless (and (string-match-p
                "\\`\\(?:[01][0-9]\\|2[0-3]\\):[0-5][0-9]\\'" value)
               (= (% (string-to-number (substring value 3 5)) 15) 0))
    (error "%s must be an HH:MM clock aligned to 15 minutes" key))
  value)

(defun my/lifeos-solver--parse-duration (key value &optional positive)
  "Parse quantum-aligned H:MM VALUE for KEY, optionally requiring POSITIVE."
  (let ((minutes (my/lifeos--duration-minutes value)))
    (when (or (/= (% minutes 15) 0) (and positive (<= minutes 0)))
      (error "%s must be %sa 15-minute-aligned H:MM duration"
             key (if positive "positive and " "")))
    minutes))

(defun my/lifeos-solver--parse-toggle (key value)
  "Parse strict yes/no VALUE for KEY."
  (pcase (downcase value)
    ("yes" t)
    ("no" nil)
    (_ (error "%s must be yes or no" key))))

(defun my/lifeos-solver--parse-travel-pair (key value)
  "Parse BEFORE / AFTER durations from VALUE for KEY."
  (unless (string-match "\\`\\([^/]+\\)/\\([^/]+\\)\\'" value)
    (error "%s must be BEFORE / AFTER using H:MM durations" key))
  (let ((before (string-trim (match-string 1 value)))
        (after (string-trim (match-string 2 value))))
    (cons (my/lifeos-solver--parse-duration key before)
          (my/lifeos-solver--parse-duration key after))))

(defun my/lifeos-solver--parse-configuration-rows (rows source-id)
  "Parse strict Key/Value ROWS from SOURCE-ID with whole-table semantics."
  (let ((header (car rows)) (seen (make-hash-table :test #'equal))
        values travel-defaults issues)
    (unless (equal header '("Key" "Value"))
      (push "Solver configuration header must be exactly | Key | Value |." issues))
    (dolist (row (cdr rows))
      (if (/= (length row) 2)
          (push (format "Malformed Solver configuration row: %S." row) issues)
        (let ((key (car row)) (value (cadr row)))
          (cond
           ((gethash key seen)
            (push (format "Duplicate Solver configuration key: %s." key) issues))
           ((and (string-prefix-p "Travel default: " key)
                 (> (length key) (length "Travel default: ")))
            (puthash key t seen)
            (condition-case error-data
                (push (cons (downcase (substring key (length "Travel default: ")))
                            (my/lifeos-solver--parse-travel-pair key value))
                      travel-defaults)
              (error (push (concat (error-message-string error-data) ".") issues))))
           ((not (member key my/lifeos-solver--configuration-keys))
            (push (format "Unknown Solver configuration key: %s." key) issues))
           (t
            (puthash key t seen)
            (condition-case error-data
                (pcase key
                  ("Sleep earliest start"
                   (setq values (plist-put values :sleep-earliest
                                           (my/lifeos-solver--parse-clock key value))))
                  ("Sleep latest end"
                   (setq values (plist-put values :sleep-latest
                                           (my/lifeos-solver--parse-clock key value))))
                  ("Sleep minimum"
                   (setq values (plist-put values :sleep-minimum
                                           (my/lifeos-solver--parse-duration key value t))))
                  ("Default safety buffer"
                   (setq values (plist-put values :default-safety-buffer
                                           (my/lifeos-solver--parse-duration key value))))
                  ("Daily reserve"
                   (setq values (plist-put values :daily-reserve
                                           (my/lifeos-solver--parse-duration key value))))
                  ("Weekly reserve"
                   (setq values (plist-put values :weekly-reserve
                                           (my/lifeos-solver--parse-duration key value))))
                  ("Reserve block"
                   (setq values (plist-put values :reserve-block
                                           (my/lifeos-solver--parse-duration key value t))))
                  ("Known travel default"
                   (push (cons "default"
                               (my/lifeos-solver--parse-travel-pair key value))
                         travel-defaults))
                  ("Unknown travel default"
                   (setq values (plist-put values :unknown-travel
                                           (my/lifeos-solver--parse-travel-pair key value))))
                  ("Remote setup"
                   (setq values (plist-put values :remote-setup
                                           (my/lifeos-solver--parse-duration key value))))
                  ("Stress estimate overrun enabled"
                   (setq values (plist-put values :stress-estimate-enabled
                                           (my/lifeos-solver--parse-toggle key value))))
                  ("Stress estimate overrun percent"
                   (unless (string-match-p "\\`[1-9][0-9]*\\'" value)
                     (error "%s must be a positive integer" key))
                   (setq values (plist-put values :stress-estimate-percent
                                           (string-to-number value))))
                  ("Stress lose largest Deep window enabled"
                   (setq values (plist-put values :stress-deep-enabled
                                           (my/lifeos-solver--parse-toggle key value))))
                  ("Stress unexpected appointment enabled"
                   (setq values (plist-put values :stress-appointment-enabled
                                           (my/lifeos-solver--parse-toggle key value))))
                  ("Stress unexpected appointment duration"
                   (setq values (plist-put values :stress-appointment-minutes
                                           (my/lifeos-solver--parse-duration key value t)))))
              (error (push (concat (error-message-string error-data) ".") issues))))))))
    (dolist (key my/lifeos-solver--configuration-keys)
      (unless (gethash key seen)
        (push (format "Missing Solver configuration key: %s." key) issues)))
    (setq values
          (plist-put values :sleep
                     (and (plist-member values :sleep-earliest)
                          (plist-member values :sleep-latest)
                          (plist-member values :sleep-minimum)
                          (list :earliest-start (plist-get values :sleep-earliest)
                                :latest-end (plist-get values :sleep-latest)
                                :minimum-minutes (plist-get values :sleep-minimum)))))
    (when-let* ((sleep (plist-get values :sleep)))
      (let* ((clock-minute
              (lambda (clock)
                (+ (* 60 (string-to-number (substring clock 0 2)))
                   (string-to-number (substring clock 3 5)))))
             (start (funcall clock-minute (plist-get sleep :earliest-start)))
             (end (funcall clock-minute (plist-get sleep :latest-end)))
             (envelope (if (> end start) (- end start)
                         (+ (- end start) (* 24 60)))))
        (when (or (zerop envelope)
                  (> (plist-get sleep :minimum-minutes) envelope))
          (push "Sleep minimum must fit inside the nightly sleep envelope."
                issues))))
    (setq values (plist-put values :travel-defaults (nreverse travel-defaults)))
    (list :values values :source-id source-id
          :evidence (my/lifeos-solver--evidence source-id "solver-configuration")
          :issues (nreverse issues) :table-present t)))

(defun my/lifeos-solver--configuration (week-start)
  "Resolve strict solver configuration for WEEK-START without writing Org."
  (let* ((weekly (my/lifeos--week-marker week-start))
         (weekly-rows (my/lifeos-solver--configuration-table weekly))
         (defaults (my/lifeos--planning-heading-marker "Recurring defaults"))
         (default-rows (and (not weekly-rows)
                            (my/lifeos-solver--configuration-table defaults))))
    (cond
     (weekly-rows
      (my/lifeos-solver--parse-configuration-rows
       weekly-rows (format "solver-configuration:week:%s" week-start)))
     (default-rows
      (my/lifeos-solver--parse-configuration-rows
       default-rows "solver-configuration:recurring-defaults"))
     (t
      (list :values (my/lifeos-solver--configuration-defaults)
            :source-id "solver-configuration:defcustom"
            :evidence (my/lifeos-solver--evidence
                       "solver-configuration:defcustom" "solver-configuration")
             :issues nil :table-present nil)))))

(defun my/lifeos-settings--insert-configuration-table (parent-marker)
  "Insert a complete Solver configuration table below PARENT-MARKER."
  (let ((validation (my/lifeos-solver--parse-configuration-rows
                     my/lifeos-solver--configuration-template-rows "template")))
    (when-let* ((issues (plist-get validation :issues)))
      (error "Internal Solver configuration template is invalid: %s"
             (string-join issues "; ")))
    (with-current-buffer (marker-buffer parent-marker)
      (save-excursion
        (goto-char parent-marker)
        (let ((level (org-outline-level)))
          (org-end-of-subtree t t)
          (unless (bolp) (insert "\n"))
          (insert (make-string (1+ level) ?*) " Solver configuration\n")
          (dolist (row my/lifeos-solver--configuration-template-rows)
            (insert "| " (string-join row " | ") " |\n"))
          (forward-line (- (length my/lifeos-solver--configuration-template-rows)))
          (org-table-align))))))

(defun my/lifeos-settings--planning-buffer ()
  "Return the authoritative planning.org buffer."
  (find-file-noselect (expand-file-name "planning.org" org-directory)))

(defun my/lifeos-settings--create-policy-parent (weekly)
  "Create and return a missing policy parent when WEEKLY is non-nil."
  (let ((buffer (my/lifeos-settings--planning-buffer))
        (week (my/lifeos--current-week-start)))
    (with-current-buffer buffer
      (org-with-wide-buffer
       (goto-char (point-max))
       (unless (bolp) (insert "\n"))
       (let ((marker (copy-marker (point))))
         (if weekly
             (insert (format "* %s #week\n:PROPERTIES:\n:WEEK_START: %s\n:END:\n"
                             week week))
           (insert "* Recurring defaults\n"))
         marker)))))

(defun my/lifeos-settings--visit-policy (weekly)
  "Visit recurring policy, or the current week when WEEKLY is non-nil."
  (let* ((week (my/lifeos--current-week-start))
         (marker (if weekly
                     (my/lifeos--week-marker week)
                   (my/lifeos--planning-heading-marker "Recurring defaults")))
         (label (if weekly
                    (format "current-week override (%s)" week)
                  "recurring policy")))
    (unless marker
      (when (y-or-n-p
             (format "No %s exists. Create it with a complete Solver configuration? "
                     label))
        (setq marker (my/lifeos-settings--create-policy-parent weekly))
        (my/lifeos-settings--insert-configuration-table marker)))
    (unless marker
      (user-error "No %s exists; planning.org was not changed" label))
    (pop-to-buffer (marker-buffer marker))
    (goto-char marker)
    (org-show-context)
    (unless (my/lifeos-solver--configuration-table marker)
      (when (y-or-n-p
             (format "No complete Solver configuration is under %s. Insert one? "
                     label))
        (my/lifeos-settings--insert-configuration-table marker)))
    (message "%s is authoritative here; a complete weekly table replaces recurring policy"
             (capitalize label))))

(defun my/lifeos-settings--visit-project ()
  "Visit project-specific settings at the nearest explicit project."
  (let ((marker (and (derived-mode-p 'org-mode)
                     (my/lifeos--nearest-project-marker))))
    (unless marker
      (user-error "Place point inside an explicit #project before opening project overrides"))
    (pop-to-buffer (marker-buffer marker))
    (goto-char marker)
    (org-show-context)
    (message "Project overrides live here; SAFETY_BUFFER overrides recurring and weekly safety policy")))

(defun my/lifeos-settings-open-manual ()
  "Open the LifeOS configuration manual."
  (interactive)
  (unless (file-readable-p my/lifeos-manual-file)
    (user-error "LifeOS manual is missing: %s" my/lifeos-manual-file))
  (find-file my/lifeos-manual-file)
  (goto-char (point-min))
  (when (re-search-forward "^\\*+ .*Configuration" nil t)
    (org-back-to-heading t)))

(defun my/lifeos-settings ()
  "Open one guided LifeOS configuration destination.

Fixed property vocabularies come from code.  Emacs preferences are fallbacks;
recurring and complete weekly tables are authoritative planning policy, and
supported project properties are the most specific override."
  (interactive)
  (pcase (completing-read
          "LifeOS settings: "
          '("Emacs preferences (fallbacks)"
            "Recurring planning policy (authoritative)"
            "This week's policy override (complete replacement)"
            "Project overrides at point"
            "Configuration manual") nil t)
    ("Emacs preferences (fallbacks)" (customize-group 'my/lifeos))
    ("Recurring planning policy (authoritative)"
     (my/lifeos-settings--visit-policy nil))
    ("This week's policy override (complete replacement)"
     (my/lifeos-settings--visit-policy t))
    ("Project overrides at point" (my/lifeos-settings--visit-project))
    ("Configuration manual" (my/lifeos-settings-open-manual))))

(defun my/lifeos-solver--deadline-minute (deadline)
  "Return exclusive end-of-day epoch minute for Org DEADLINE."
  (when deadline
    (my/lifeos-solver--minute
     (my/lifeos--date-time
      (my/lifeos--date-add-days (my/lifeos--deadline-date deadline) 1)
      "00:00"))))

(defun my/lifeos-solver--record-at-marker (record function)
  "Call FUNCTION at RECORD's marker."
  (when-let* ((marker (plist-get record :marker))
              ((marker-buffer marker)))
    (with-current-buffer (marker-buffer marker)
      (save-excursion
        (goto-char marker)
        (funcall function)))))

(defun my/lifeos-solver--direct-clocked-minutes-in-range (record start end)
  "Return RECORD's direct clock minutes from START through END."
  (or (my/lifeos-solver--record-at-marker
       record
       (lambda ()
         (let ((bounds (my/lifeos--entry-section-bounds)))
           (if (not bounds)
               0
             (save-restriction
               (narrow-to-region (line-beginning-position) (cdr bounds))
               (org-clock-sum start end)
               org-clock-file-total-minutes)))))
      0))

(defun my/lifeos-solver--calendar-selector-allocation
    (selector start end &optional source-markers)
  "Return (MINUTES . EVIDENCE) for timed calendar sources matching SELECTOR.
All-day events, generated travel, and remote setup are not allocation sources."
  (let ((file (expand-file-name "calendar.org" org-directory))
        (minutes 0)
        evidence)
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
                (let* ((raw-id (or (org-entry-get nil "entry-id")
                                   (org-entry-get nil "ID")
                                   (org-entry-get nil "event-id")
                                   (format "%s:%d:%s:%s"
                                           (or buffer-file-name (buffer-name))
                                           (line-beginning-position)
                                           (my/lifeos-solver--minute (car range))
                                           (my/lifeos-solver--minute (cdr range)))))
                       (source-id (concat "calendar:" (secure-hash 'sha1 raw-id))))
                  (when source-markers
                    (puthash source-id (copy-marker (point)) source-markers))
                  (cl-incf minutes
                           (- (my/lifeos-solver--minute overlap-end)
                              (my/lifeos-solver--minute overlap-start)))
                  (push (my/lifeos-solver--evidence
                         source-id "calendar-role"
                         (plist-get source :calendar-role))
                        evidence))))
          nil 'file))))
    (cons minutes (nreverse evidence))))

(defun my/lifeos-solver--virtual-selector-sources (projects)
  "Return selector evidence for virtual chunks derived from PROJECTS."
  (let (sources)
    (dolist (project projects (nreverse sources))
      (when (and (plist-get project :id)
                 (eq (plist-get project :definition-status) 'coarse))
        (let* ((remaining (plist-get project :unallocated-effort-minutes))
               (chunk (my/lifeos--aligned-positive-duration-minutes
                       (plist-get project :planning-chunk)))
               (count (and remaining chunk (ceiling remaining chunk))))
          (dotimes (index (or count 0))
            (push (list :id (format "%s:virtual:%d"
                                    (plist-get project :id) (1+ index))
                        :source-type 'task
                        :project-id (plist-get project :id)
                        :work-mode (plist-get project :default-work-mode)
                        :tags (plist-get project :tags)
                        :properties (plist-get project :properties)
                        :project-tags (plist-get project :tags)
                        :project-properties (plist-get project :properties))
                  sources)))))))

(defun my/lifeos-solver--intention-json
    (intention records week-times &optional source-markers)
  "Normalize one selected INTENTION using source-aware RECORDS and WEEK-TIMES."
  (let* ((selector (plist-get intention :selector))
               (matches (seq-filter
                          (lambda (record)
                            (my/lifeos-selector-match-p selector record))
                          records))
               (calendar (my/lifeos-solver--calendar-selector-allocation
                          selector (car week-times) (cadr week-times)
                          source-markers))
               (actual (+ (car calendar)
                          (apply #'+
                                 (mapcar
                                  (lambda (record)
                                    (my/lifeos-solver--direct-clocked-minutes-in-range
                                     record (car week-times) (cadr week-times)))
                                  matches)))))
    `((id . ,(plist-get intention :id))
      (name . ,(plist-get intention :name))
      (minimumMinutes . ,(or (plist-get intention :minimum) :null))
      (targetMinutes . ,(or (plist-get intention :target) :null))
      (maximumMinutes . ,(or (plist-get intention :maximum) :null))
      (actualMinutes . ,actual)
      (windowStart . ,(my/lifeos-solver--minute (car week-times)))
      (windowEnd . ,(my/lifeos-solver--minute (cadr week-times)))
      (matchedTaskIds . ,(vconcat (delq nil (mapcar
                                             (lambda (record) (plist-get record :id))
                                             matches))))
       (matchEvidence . ,(vconcat
                          (cons (my/lifeos-solver--evidence
                                 (plist-get intention :id) "selector"
                                 (plist-get intention :selector-text))
                                (cdr calendar)))))))

(defun my/lifeos-solver--intentions
    (week-start records projects &optional source-markers)
  "Return normalized intentions, hard issues, and assumptions for WEEK-START."
  (let ((week-times (my/lifeos--week-times week-start))
        (sources (append records
                         (my/lifeos-solver--virtual-selector-sources projects)))
        intentions issues assumptions)
    (condition-case error-data
        (if-let* ((selected (my/lifeos-intentions-for-week week-start)))
            (dolist (intention selected)
              (push (my/lifeos-solver--intention-json
                     intention sources week-times source-markers)
                    intentions))
          (push "No allocation targets are configured." assumptions))
      (error (push (concat (error-message-string error-data) ".") issues)))
    (list :intentions (vconcat (nreverse intentions))
          :issues (nreverse issues)
          :assumptions (nreverse assumptions))))

(defun my/lifeos-solver--canonical-availability (windows)
  "Return non-overlapping normalized availability from WINDOWS."
  (let* ((normalized
          (mapcar (lambda (window)
                    (list :start (my/lifeos-solver--minute (plist-get window :start))
                          :end (my/lifeos-solver--minute (plist-get window :end))
                          :modes (sort (delete-dups
                                        (copy-sequence (plist-get window :modes)))
                                       #'string<)))
                  windows))
         (boundaries (sort (delete-dups
                            (apply #'append
                                   (mapcar (lambda (window)
                                             (list (plist-get window :start)
                                                   (plist-get window :end)))
                                           normalized)))
                           #'<))
         pieces)
    (while (cdr boundaries)
      (let* ((start (car boundaries))
             (end (cadr boundaries))
             (covering (seq-filter
                        (lambda (window)
                          (and (<= (plist-get window :start) start)
                               (>= (plist-get window :end) end)))
                        normalized))
             (modes (sort (delete-dups
                           (apply #'append
                                  (mapcar (lambda (window)
                                            (copy-sequence (plist-get window :modes)))
                                          covering)))
                          #'string<)))
        (when modes
          (if (and pieces
                   (= (plist-get (car pieces) :end) start)
                   (equal (plist-get (car pieces) :modes) modes))
              (plist-put (car pieces) :end end)
            (push (list :start start :end end :modes modes) pieces))))
      (setq boundaries (cdr boundaries)))
    (vconcat
     (cl-loop for window in (nreverse pieces)
              for index from 1
              collect `((id . ,(format "availability:%d" index))
                        (start . ,(plist-get window :start))
                        (end . ,(plist-get window :end))
                        (modes . ,(vconcat (plist-get window :modes)))
                        (kind . "availability"))))))

(defun my/lifeos-solver--calendar-blocks (start end &optional configuration source-markers)
  "Return (BLOCKS ISSUES . ASSUMPTIONS) for calendar events in START through END."
  (let* ((configuration (or configuration
                            (my/lifeos-solver--configuration-defaults)))
        (file (expand-file-name "calendar.org" org-directory))
        (travel-defaults (plist-get configuration :travel-defaults))
        (unknown-travel (plist-get configuration :unknown-travel))
        (remote-setup (plist-get configuration :remote-setup))
        blocks issues assumptions)
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-map-entries
          (lambda ()
            (when-let* ((range (my/lifeos--calendar-busy-range-at-point))
                        ((time-less-p (car range) end))
                        ((time-less-p start (cdr range))))
               (let* ((raw-id (or (org-entry-get nil "entry-id")
                                  (org-entry-get nil "ID")
                                  (org-entry-get nil "event-id")
                                  (format "%s:%d:%s:%s"
                                          (or buffer-file-name (buffer-name))
                                          (line-beginning-position)
                                          (my/lifeos-solver--minute (car range))
                                          (my/lifeos-solver--minute (cdr range)))))
                     (id (concat "calendar:" (secure-hash 'sha1 raw-id)))
                     (source-id id)
                      (attendance-text (org-entry-get nil "ATTENDANCE"))
                      (compatibility (downcase
                                      (or (org-entry-get nil "TRAVEL_REQUIRED") "")))
                      (attendance
                       (cond
                        ((member (downcase (or attendance-text ""))
                                 '("remote" "in-person"))
                         (downcase attendance-text))
                        ((equal compatibility "yes") "in-person")
                        ((equal compatibility "no") "remote")
                        (t "unknown")))
                      (event-type (downcase
                                   (or (org-entry-get nil "GCAL_EVENT_TYPE")
                                       "unknown")))
                       (typed-default
                        (and (equal attendance "in-person")
                             (cdr (assoc-string event-type travel-defaults t))))
                       (defaults (or typed-default unknown-travel))
                      (before-text (org-entry-get nil "TRAVEL_BEFORE"))
                      (after-text (org-entry-get nil "TRAVEL_AFTER"))
                      (before-override
                       (and before-text
                            (condition-case nil
                                (my/lifeos--effort-minutes before-text)
                              (error :invalid))))
                      (after-override
                       (and after-text
                            (condition-case nil
                                (my/lifeos--effort-minutes after-text)
                              (error :invalid))))
                      (before (or (and (numberp before-override) before-override)
                                  (car-safe defaults)))
                      (after (or (and (numberp after-override) after-override)
                                 (cdr-safe defaults)))
                     (start-minute (my/lifeos-solver--minute (car range)))
                      (end-minute (my/lifeos-solver--minute (cdr range))))
                 (when (and attendance-text
                            (not (member (downcase attendance-text)
                                         '("remote" "in-person"))))
                   (push (format "%s has invalid ATTENDANCE %S; expected remote or in-person."
                                 source-id attendance-text)
                         issues))
                 (when (eq before-override :invalid)
                   (push (format "%s has invalid TRAVEL_BEFORE %S."
                                 source-id before-text)
                         issues))
                 (when (eq after-override :invalid)
                   (push (format "%s has invalid TRAVEL_AFTER %S."
                                 source-id after-text)
                         issues))
                 (when source-markers
                   (puthash source-id (copy-marker (point)) source-markers))
                 (push `((id . ,id) (start . ,start-minute) (end . ,end-minute)
                         (kind . "calendar")
                         (evidence . ,(my/lifeos-solver--evidence source-id "calendar")))
                       blocks)
                 (cond
                  ((equal attendance "remote")
                   (if (numberp remote-setup)
                       (when (> remote-setup 0)
                         (push `((id . ,(concat id ":remote-setup"))
                                 (start . ,(- start-minute remote-setup))
                                 (end . ,start-minute)
                                 (kind . "travel")
                                 (evidence . ,(my/lifeos-solver--evidence
                                               source-id "remote-setup"
                                               "configured pre-event setup")))
                               blocks)
                         (push (format "%s is remote; a %d-minute setup block was assumed."
                                       source-id remote-setup)
                               assumptions))
                     (push (format "Remote setup is unconfigured for %s." source-id)
                           issues)))
                  ((member attendance '("in-person" "unknown"))
                   (when (equal attendance "unknown")
                     (push (format "%s has no explicit ATTENDANCE; conservative in-person travel was assumed."
                                   source-id)
                           assumptions))
                   (if (and before after)
                       (progn
                         (when (> before 0)
                           (push `((id . ,(concat id ":travel-before"))
                                  (start . ,(- start-minute before)) (end . ,start-minute)
                                  (kind . "travel")
                                  (evidence . ,(my/lifeos-solver--evidence
                                                 source-id
                                                 (if (numberp before-override) "travel-override"
                                                   (if typed-default
                                                       "travel-typed-default"
                                                     "travel-unknown-default"))
                                                 event-type)))
                                 blocks))
                         (when (> after 0)
                          (push `((id . ,(concat id ":travel-after"))
                                  (start . ,end-minute) (end . ,(+ end-minute after))
                                  (kind . "travel")
                                  (evidence . ,(my/lifeos-solver--evidence
                                                 source-id
                                                 (if (numberp after-override) "travel-override"
                                                   (if typed-default
                                                       "travel-typed-default"
                                                     "travel-unknown-default"))
                                                 event-type)))
                                 blocks))
                         (unless (and (numberp before-override)
                                      (numberp after-override))
                           (push (format "%s uses %s travel defaults for event type %s."
                                         source-id
                                         (if typed-default "typed" "unknown-location")
                                         event-type)
                                 assumptions)))
                     (push (format "Travel is required for %s but no complete override or conservative default is configured."
                                   source-id)
                           issues))))))
           nil 'file))))
    (cons (vconcat (nreverse blocks))
          (cons (nreverse issues) (nreverse assumptions))))))

(defun my/lifeos-solver--sleep-blocks (horizon-start horizon-end &optional sleep)
  "Return (BLOCKS . ISSUES) for sleep inside the assurance horizon."
  (when sleep
    (let* ((earliest (plist-get sleep :earliest-start))
            (latest (plist-get sleep :latest-end))
            (minimum (plist-get sleep :minimum-minutes))
           (date (my/lifeos--date-add-days
                  (format-time-string "%Y-%m-%d" horizon-start) -1))
            blocks issues index)
      (while (time-less-p (my/lifeos--date-time date earliest) horizon-end)
        (let* ((start (my/lifeos--date-time date earliest))
               (same-day-end (my/lifeos--date-time date latest))
               (end (if (time-less-p start same-day-end)
                        same-day-end
                      (my/lifeos--date-time (my/lifeos--date-add-days date 1) latest))))
          (when (and (time-less-p start horizon-end) (time-less-p horizon-start end))
            (setq index (1+ (or index 0)))
             (let* ((id (format "sleep:%s" date))
                    (start-minute (max (my/lifeos-solver--minute start)
                                       (my/lifeos-solver--minute horizon-start)))
                    (end-minute (my/lifeos-solver--minute end)))
               (if (< (- end-minute start-minute) minimum)
                   (push (format "%s has only %d minutes remaining after the planning horizon starts; the %d-minute sleep minimum cannot fit."
                                 id (- end-minute start-minute) minimum)
                         issues)
                 (push `((id . ,id)
                         (envelopeStart . ,start-minute)
                         (envelopeEnd . ,end-minute)
                         (minimumMinutes . ,minimum)
                         (evidence . ,(my/lifeos-solver--evidence id "sleep-config")))
                       blocks)))))
         (setq date (my/lifeos--date-add-days date 1)))
       (cons (vconcat (nreverse blocks)) (nreverse issues)))))

(defun my/lifeos-solver--reserve-chunks (prefix start end minutes block-minutes)
  "Return reserve blocks named PREFIX within START and END."
  (when (> minutes 0)
    (let* ((count (floor minutes block-minutes))
           (base-units (/ (/ minutes 15) count))
           (extra-units (% (/ minutes 15) count))
           blocks)
      (dotimes (offset count)
        (let* ((index (1+ offset))
               (size (* 15 (+ base-units (if (< offset extra-units) 1 0))))
               (id (format "%s:%d" prefix index)))
        (push `((id . ,id)
                (envelopeStart . ,(my/lifeos-solver--minute start))
                (envelopeEnd . ,(my/lifeos-solver--minute end))
                (minimumMinutes . ,size)
                (evidence . ,(my/lifeos-solver--evidence id "reserve-config")))
                blocks)))
      (nreverse blocks))))

(defun my/lifeos-solver--reserve-policy-issue (name minutes block-minutes)
  "Return a safety issue when NAME policy cannot form valid reserve chunks."
  (cond
   ((zerop minutes) nil)
   ((<= block-minutes 0)
    (format "%s reserve is enabled but its minimum block is not positive." name))
   ((< minutes block-minutes)
    (format "%s reserve (%d minutes) is smaller than the %d-minute minimum block."
            name minutes block-minutes))
   ((or (/= (% minutes 15) 0) (/= (% block-minutes 15) 0))
    (format "%s reserve and minimum block must align to the 15-minute scheduling quantum."
            name))))

(defun my/lifeos-solver--availability-overlaps-p (availability start end)
  "Return non-nil when AVAILABILITY overlaps START through END."
  (seq-some (lambda (window)
              (and (< (alist-get 'start window) end)
                   (< start (alist-get 'end window))))
            availability))

(defun my/lifeos-solver--reserve-window-issue
    (name start end minutes block-minutes availability)
  "Return an issue when NAME reserve cannot fit usable START through END."
  (when (> minutes 0)
    (let* ((sizes (mapcar (lambda (block) (alist-get 'minimumMinutes block))
                          (my/lifeos-solver--reserve-chunks
                           "check" (seconds-to-time (* start 60))
                           (seconds-to-time (* end 60)) minutes block-minutes)))
           (usable-lengths
            (delq nil
                  (mapcar
                   (lambda (window)
                     (let ((overlap-start (max start (alist-get 'start window)))
                           (overlap-end (min end (alist-get 'end window))))
                       (and (> overlap-end overlap-start)
                            (- overlap-end overlap-start))))
                   availability)))
           (capacity (apply #'+ usable-lengths))
           (longest (if usable-lengths (apply #'max usable-lengths) 0)))
      (when (or (> minutes capacity)
                (> (apply #'max sizes) longest))
        (format "%s reserve cannot fit in usable availability within its envelope."
                name)))))

(defun my/lifeos-solver--reserve-blocks
    (horizon-start horizon-end availability &optional configuration)
  "Return (BLOCKS . ISSUES) for reserve policy in the planning horizon."
  (let* ((configuration (or configuration
                            (my/lifeos-solver--configuration-defaults)))
        (daily (plist-get configuration :daily-reserve))
        (weekly (plist-get configuration :weekly-reserve))
        (block-minutes (plist-get configuration :reserve-block))
        blocks issues)
    (when (and (numberp daily) (numberp weekly) (numberp block-minutes))
      (dolist (policy `(("Daily" . ,daily) ("Weekly" . ,weekly)))
        (when-let* ((issue (my/lifeos-solver--reserve-policy-issue
                            (car policy) (cdr policy) block-minutes)))
          (push issue issues)))
      (unless issues
        (let ((date (format-time-string "%Y-%m-%d" horizon-start)))
          (while (time-less-p (my/lifeos--date-time date "00:00") horizon-end)
            (let* ((day-start (my/lifeos--date-time date "00:00"))
                   (day-end (my/lifeos--date-time
                             (my/lifeos--date-add-days date 1) "00:00"))
                   (start (max (my/lifeos-solver--minute horizon-start)
                               (my/lifeos-solver--minute day-start)))
                   (end (min (my/lifeos-solver--minute horizon-end)
                             (my/lifeos-solver--minute day-end))))
              (when (and (> end start)
                         (my/lifeos-solver--availability-overlaps-p
                          availability start end))
                (let ((issue (my/lifeos-solver--reserve-window-issue
                              (format "Daily reserve for %s" date) start end
                               daily block-minutes
                              availability)))
                  (if issue
                      (push issue issues)
                    (setq blocks
                          (nconc blocks
                                 (my/lifeos-solver--reserve-chunks
                                  (concat "daily-reserve:" date)
                                  (seconds-to-time (* start 60))
                                  (seconds-to-time (* end 60))
                                   daily block-minutes)))))))
            (setq date (my/lifeos--date-add-days date 1))))
        (let* ((horizon-date (format-time-string "%Y-%m-%d" horizon-start))
               (weekday (string-to-number (format-time-string "%u" horizon-start)))
               (week-start (my/lifeos--date-add-days horizon-date (- 1 weekday))))
          (while (time-less-p (my/lifeos--date-time week-start "00:00") horizon-end)
            (let* ((week-end (my/lifeos--date-add-days week-start 7))
                   (start (max (my/lifeos-solver--minute horizon-start)
                               (my/lifeos-solver--minute
                                (my/lifeos--date-time week-start "00:00"))))
                   (end (min (my/lifeos-solver--minute horizon-end)
                             (my/lifeos-solver--minute
                              (my/lifeos--date-time week-end "00:00")))))
               (when (and (> weekly 0)
                         (> end start))
                (if (my/lifeos-solver--availability-overlaps-p
                     availability start end)
                    (let ((issue (my/lifeos-solver--reserve-window-issue
                                  (format "Weekly reserve for %s" week-start)
                                   start end weekly block-minutes
                                  availability)))
                      (if issue
                          (push issue issues)
                        (setq blocks
                              (nconc blocks
                                     (my/lifeos-solver--reserve-chunks
                                      (concat "weekly-reserve:" week-start)
                                      (seconds-to-time (* start 60))
                                      (seconds-to-time (* end 60))
                                       weekly block-minutes)))))
                  (push (format "Weekly reserve for %s has no usable availability."
                                week-start)
                        issues)))
              (setq week-start week-end))))))
    (cons (vconcat blocks) (nreverse issues))))

(defun my/lifeos-solver--wait-release-minute (record now)
  "Return RECORD's future WAIT_UNTIL as an epoch minute, or nil.
NOW determines whether a parseable release remains in the future."
  (when (equal (plist-get record :state) "WAITING")
    (when-let* ((text (my/lifeos-solver--record-at-marker
                       record (lambda () (org-entry-get nil "WAIT_UNTIL")))))
      (condition-case nil
          (let ((minute (my/lifeos-solver--minute (org-time-string-to-time text))))
            (and (> minute (my/lifeos-solver--minute now)) minute))
        (error nil)))))

(defun my/lifeos-solver--task-json (record task-ids mandatory-ids now)
  "Return normalized protocol task for RECORD at NOW."
  (let* ((id (plist-get record :id))
         (state (plist-get record :state))
         (scheduled (my/lifeos--record-scheduled-time record))
         (deadline (my/lifeos-solver--deadline-minute (plist-get record :deadline)))
         (own-deadline
          (my/lifeos-solver--record-at-marker
           record (lambda () (org-entry-get nil "DEADLINE"))))
         (deadline-source
          (cond ((null (plist-get record :deadline)) :null)
                (own-deadline "task")
                (t "project")))
         (mandatory (gethash id mandatory-ids))
         (release (my/lifeos-solver--wait-release-minute record now)))
    `((id . ,id)
      (projectId . ,(or (plist-get record :project-id) :null))
      (durationMinutes . ,(or (and (plist-get record :minutes)
                                   (my/lifeos--quantize-minutes
                                    (plist-get record :minutes)))
                              :null))
       (workMode . ,(plist-get record :work-mode))
       (deadline . ,(or deadline :null))
       (deadlineSource . ,deadline-source)
      (fixedStart . ,(or (and scheduled (my/lifeos-solver--minute scheduled)) :null))
      (preferredStart . :null)
       (prerequisiteIds
        . ,(vconcat (seq-filter (lambda (target) (gethash target task-ids))
                                (delete-dups (copy-sequence
                                              (plist-get record :targets))))))
      (state . ,state)
       (priority . ,(plist-get record :priority))
       (impact . ,(plist-get record :impact))
       (mandatory . ,(if mandatory t :false))
       (releaseTime . ,(or release :null))
       (unresolvedWaiting . ,(if (and (equal state "WAITING") (not release))
                                 t :false))
       (evidence . ,(my/lifeos-solver--evidence id "task"))
       (workType . "explicit")
       (virtualWork . :null))))

(defun my/lifeos-solver--project-safety-buffer (project)
  "Return parsed safety-buffer metadata for PROJECT."
  (my/lifeos-solver--record-at-marker
   project
   (lambda ()
     (when-let* ((value (org-entry-get nil "SAFETY_BUFFER")))
       (condition-case nil
           (let ((minutes (my/lifeos--effort-minutes value)))
             (if (and (integerp minutes) (>= minutes 0))
                 (list :value minutes)
               (list :issue
                     (format "Project %s has malformed SAFETY_BUFFER %S."
                             (plist-get project :id) value))))
         (error
          (list :issue
                (format "Project %s has malformed SAFETY_BUFFER %S."
                        (plist-get project :id) value))))))))

(defun my/lifeos-solver--project-json (project &optional safety-buffer)
  "Return normalized protocol PROJECT using parsed SAFETY-BUFFER metadata."
  (let ((id (plist-get project :id))
        (safety-buffer (or safety-buffer
                           (my/lifeos-solver--project-safety-buffer project))))
    `((id . ,id)
      (deadline . ,(or (my/lifeos-solver--deadline-minute
                         (plist-get project :deadline)) :null))
       (safetyBufferMinutes . ,(or (plist-get safety-buffer :value) :null))
       (evidence . ,(my/lifeos-solver--evidence id "project"))
       (definitionStatus . ,(upcase (symbol-name
                                     (or (plist-get project :definition-status)
                                         'incomplete))))
       (commitment . ,(upcase (symbol-name
                               (or (plist-get project :commitment) 'committed))))
       (projectEffortMinutes . ,(or (plist-get project :project-effort-minutes)
                                    :null))
       (explicitEffortMinutes . ,(or (plist-get project :explicit-effort-minutes) 0))
       (remainingExplicitEffortMinutes
        . ,(or (plist-get project :explicit-remaining-minutes) 0))
       (virtualEffortMinutes . ,(or (plist-get project :unallocated-effort-minutes) 0))
        (defaultWorkMode
         . ,(let ((value (plist-get project :default-work-mode)))
              (if (and (stringp value) (not (string-empty-p value))) value :null)))
       (planningChunkMinutes
        . ,(or (my/lifeos--aligned-positive-duration-minutes
                (plist-get project :planning-chunk)) :null))
        (estimateConfidence
         . ,(let ((value (plist-get project :estimate-confidence)))
              (if (and (stringp value) (not (string-empty-p value))) value :null)))
       (diagnostics
        . ,(vconcat
            (mapcar
             (lambda (diagnostic)
               (my/lifeos-solver--evidence
                id "project-diagnostic"
                (format "%s: %s" (plist-get diagnostic :code)
                        (plist-get diagnostic :message))))
             (plist-get project :diagnostics)))))))

(defun my/lifeos-solver--virtual-task-json (project ordinal chunk-count minutes)
  "Return virtual work chunk ORDINAL of CHUNK-COUNT for PROJECT."
  (let* ((id (plist-get project :id))
         (evidence (my/lifeos-solver--evidence id "project")))
    `((id . ,(format "%s:virtual:%d" id ordinal))
      (projectId . ,id)
      (durationMinutes . ,minutes)
      (workMode . ,(plist-get project :default-work-mode))
      (deadline . ,(my/lifeos-solver--deadline-minute
                    (plist-get project :deadline)))
      (deadlineSource . "project")
      (releaseTime . :null)
      (fixedStart . :null)
      (preferredStart . :null)
      (prerequisiteIds . [])
      (state . "TODO")
      (priority . "A")
      (impact . "High")
      (mandatory . t)
      (unresolvedWaiting . :false)
      (evidence . ,evidence)
      (workType . "virtual")
      (virtualWork
       . ((projectId . ,id)
          (ordinal . ,ordinal)
          (chunkCount . ,chunk-count)
          (estimateConfidence . ,(plist-get project :estimate-confidence))
          (projectEvidence . ,evidence))))))

(defun my/lifeos-solver--virtual-tasks-json (projects)
  "Return deterministic virtual task records for coarse PROJECTS."
  (let (tasks)
    (dolist (project projects (vconcat (nreverse tasks)))
      (when (and (plist-get project :id)
                 (eq (plist-get project :definition-status) 'coarse))
        (let* ((remaining (plist-get project :unallocated-effort-minutes))
               (chunk (my/lifeos--aligned-positive-duration-minutes
                       (plist-get project :planning-chunk)))
               (count (and remaining chunk (ceiling remaining chunk))))
          (dotimes (index (or count 0))
            (let ((ordinal (1+ index)))
              (push (my/lifeos-solver--virtual-task-json
                     project ordinal count
                     (min chunk (- remaining (* index chunk))))
                    tasks))))))))

(defun my/lifeos-solver--projects-json (projects)
  "Return (PROJECTS . SAFETY-ISSUES) for PROJECTS."
  (let (output issues)
    (dolist (project projects)
      (when (plist-get project :id)
        (let ((safety-buffer (my/lifeos-solver--project-safety-buffer project)))
          (when-let* ((issue (plist-get safety-buffer :issue)))
            (push issue issues))
          (push (my/lifeos-solver--project-json project safety-buffer) output))))
    (cons (vconcat (nreverse output)) (nreverse issues))))

(defun my/lifeos-solver--mandatory-graph-issues (analysis mandatory-ids)
  "Return graph integrity issues whose source is in MANDATORY-IDS."
  (let (issues)
    (dolist (spec '((:missing-targets . "missing")
                    (:inactive-targets . "inactive")
                    (:invalid-targets . "invalid")))
      (dolist (edge (plist-get analysis (car spec)))
        (when (gethash (car edge) mandatory-ids)
          (push (format "Mandatory task %s has %s prerequisite %s."
                        (car edge) (cdr spec) (cdr edge))
                issues))))
    (dolist (cycle (plist-get analysis :cycles))
      (when (seq-some (lambda (id) (gethash id mandatory-ids)) cycle)
        (push (format "Mandatory dependency cycle: %s."
                      (string-join cycle " -> "))
              issues)))
    (nreverse issues)))

(defun my/lifeos-solver--capture-source-markers (records projects destination)
  "Copy source markers from RECORDS and PROJECTS into DESTINATION."
  (when destination
    (dolist (record (append records projects))
      (when-let* ((marker (plist-get record :marker))
                  ((marker-buffer marker)))
        (puthash (my/lifeos-solver--source-id
                  record (cond ((plist-get record :definition-status) "project")
                               ((plist-get record :project-key) "task")
                               (t "source")))
                  (copy-marker marker) destination)))))

(defun my/lifeos-solver--empty-scenario (id)
  "Return an empty protocol scenario named ID."
  (list (cons 'id id)
        (cons 'reservations (vector))
         (cons 'unlockedCommitmentIds (vector))
         (cons 'estimateChanges (vector))
         (cons 'estimateMultipliers (vector))
         (cons 'intentionChanges (vector))
         (cons 'projectChanges (vector))))

(defun my/lifeos-solver--availability-minus-busy (availability busy)
  "Return AVAILABILITY split around overlapping BUSY intervals."
  (let (output)
    (dolist (window (append availability nil))
      (let ((segments (list (cons (alist-get 'start window)
                                  (alist-get 'end window)))))
        (dolist (block (append busy nil))
          (let (next)
            (dolist (segment segments)
              (let ((start (car segment)) (end (cdr segment))
                    (busy-start (alist-get 'start block))
                    (busy-end (alist-get 'end block)))
                (if (or (<= busy-end start) (<= end busy-start))
                    (push segment next)
                  (when (< start busy-start)
                    (push (cons start (min end busy-start)) next))
                  (when (< busy-end end)
                    (push (cons (max start busy-end) end) next)))))
            (setq segments (nreverse next))))
        (dolist (segment segments)
          (push `((start . ,(car segment)) (end . ,(cdr segment))
                  (modes . ,(alist-get 'modes window)))
                output))))
    (nreverse output)))

(defun my/lifeos-solver--stress-profiles
    (records availability busy configuration)
  "Return (PROFILES . ASSUMPTIONS) generated from free AVAILABILITY.
Invalid profiles are omitted because stress profiles affect resilience only."
  (let ((free (my/lifeos-solver--availability-minus-busy availability busy))
        profiles assumptions)
    (when (plist-get configuration :stress-estimate-enabled)
      (condition-case error-data
          (let ((percent (plist-get configuration :stress-estimate-percent)))
            (if (not (and (integerp percent) (> percent 0)))
                (push "Estimate-overrun stress profile was omitted: no positive percentage is configured."
                      assumptions)
              (let (multipliers)
                (dolist (record (sort (copy-sequence records)
                                      (lambda (left right)
                                        (string< (plist-get left :id)
                                                 (plist-get right :id)))))
                  (when (plist-get record :minutes)
                    (push `((taskId . ,(plist-get record :id))
                            (percentage . ,percent))
                          multipliers)))
                (let ((scenario (my/lifeos-solver--empty-scenario
                                 "stress-scenario:estimate-overrun")))
                  (setf (alist-get 'estimateMultipliers scenario)
                        (vconcat (nreverse multipliers)))
                  (push `((id . "stress:estimate-overrun")
                          (description . ,(format "Increase known estimates by %d%%" percent))
                          (scenario . ,scenario))
                        profiles)))))
        (error
         (push (format "Estimate-overrun stress profile was omitted: %s."
                       (error-message-string error-data))
               assumptions))))
    (when (plist-get configuration :stress-deep-enabled)
      (condition-case error-data
          (let ((window
                 (car (sort
                       (seq-filter
                        (lambda (item)
                          (member "Deep" (append (alist-get 'modes item) nil)))
                        (copy-sequence free))
                       (lambda (left right)
                         (let ((left-size (- (alist-get 'end left)
                                             (alist-get 'start left)))
                               (right-size (- (alist-get 'end right)
                                              (alist-get 'start right))))
                           (if (= left-size right-size)
                               (< (alist-get 'start left) (alist-get 'start right))
                             (> left-size right-size))))))))
            (if (not window)
                (push "Lose-largest-Deep-window stress profile was omitted: no free Deep window exists."
                      assumptions)
              (let ((scenario (my/lifeos-solver--empty-scenario
                               "stress-scenario:lose-largest-deep-window")))
                (setf (alist-get 'reservations scenario)
                      `[((id . "stress-reservation:largest-deep-window")
                         (start . ,(alist-get 'start window))
                         (end . ,(alist-get 'end window))
                         (kind . "scenario-reservation"))])
                (push `((id . "stress:lose-largest-deep-window")
                        (description . "Lose the largest free Deep availability window")
                        (scenario . ,scenario))
                      profiles))))
        (error
         (push (format "Lose-largest-Deep-window stress profile was omitted: %s."
                       (error-message-string error-data))
               assumptions))))
    (when (plist-get configuration :stress-appointment-enabled)
      (condition-case error-data
          (let* ((minutes (plist-get configuration :stress-appointment-minutes))
                 (window
                  (and (integerp minutes)
                       (car (sort
                             (seq-filter
                              (lambda (item)
                                (>= (- (alist-get 'end item)
                                       (alist-get 'start item))
                                    minutes))
                              (copy-sequence free))
                             (lambda (left right)
                               (< (alist-get 'start left)
                                  (alist-get 'start right))))))))
            (cond
             ((not (and (integerp minutes) (> minutes 0)
                        (= (% minutes 15) 0)))
              (push "Unexpected-appointment stress profile was omitted: duration is not positive and quantum-aligned."
                    assumptions))
             ((not window)
              (push "Unexpected-appointment stress profile was omitted: no free availability window is large enough."
                    assumptions))
             (t
              (let* ((start (alist-get 'start window))
                     (scenario (my/lifeos-solver--empty-scenario
                                "stress-scenario:unexpected-appointment")))
                (setf (alist-get 'reservations scenario)
                      `[((id . "stress-reservation:unexpected-appointment")
                         (start . ,start) (end . ,(+ start minutes))
                         (kind . "scenario-reservation"))])
                (push `((id . "stress:unexpected-appointment")
                        (description . ,(format "Add an unexpected %d-minute appointment"
                                                minutes))
                        (scenario . ,scenario))
                      profiles)))))
        (error
         (push (format "Unexpected-appointment stress profile was omitted: %s."
                       (error-message-string error-data))
               assumptions))))
    (cons (vconcat (nreverse profiles)) (nreverse assumptions))))

(defun my/lifeos-solver--calendar-coverage (now horizon-end)
  "Return (END-MINUTE ISSUES ASSUMPTIONS) from successful sync evidence."
  (let* ((fetched my/org-gcal-last-successful-fetch-time)
         (coverage my/org-gcal-calendar-coverage-end)
         (end-minute (if coverage (my/lifeos-solver--minute coverage)
                       (my/lifeos-solver--minute now)))
         issues assumptions)
    (cond
     ((or (null fetched) (null coverage))
      (push "Calendar coverage evidence is absent; run a successful org-gcal fetch."
            issues))
     ((> (float-time (time-subtract now fetched))
         (* 60 my/lifeos-solver-calendar-coverage-max-age-minutes))
      (push (format "Calendar coverage evidence is stale; last successful fetch was %s."
                    (format-time-string "%Y-%m-%d %H:%M" fetched))
            issues))
     ((time-less-p coverage horizon-end)
      (push (format "Calendar coverage evidence ends at %s before the assurance horizon."
                    (format-time-string "%Y-%m-%d %H:%M" coverage))
            issues))
     (t
      (push (format "Calendar coverage is evidenced by the successful org-gcal fetch at %s through %s."
                    (format-time-string "%Y-%m-%d %H:%M" fetched)
                    (format-time-string "%Y-%m-%d %H:%M" coverage))
            assumptions)))
    (list end-minute (nreverse issues) (nreverse assumptions))))

(defun my/lifeos-solver-normalize
    (&optional analysis scenario now source-markers negotiation-queries)
  "Return a versioned read-only solver request.

ANALYSIS, SCENARIO, and NEGOTIATION-QUERIES provide planning input.  NOW is
injectable for tests.  When SOURCE-MARKERS is a hash table, populate it for
this request only."
  (let* ((analysis (or analysis (my/lifeos-graph-analysis)))
         (now (or now (current-time)))
         (all-records (plist-get analysis :all-records))
         (mandatory-ids (my/lifeos-solver--mandatory-closure all-records))
          (records (seq-filter
                     (lambda (record)
                       (and (my/lifeos-solver--solver-valid-p record)
                            (or (not (equal (plist-get record :state) "WAITING"))
                                (gethash (plist-get record :id) mandatory-ids)
                                (my/lifeos-solver--wait-release-minute record now))))
                     all-records))
         (task-ids (my/lifeos-solver--record-table records))
         (mandatory-invalid
          (seq-filter (lambda (record)
                        (and (my/lifeos-solver--active-record-p record)
                             (gethash (plist-get record :id) mandatory-ids)
                             (not (my/lifeos-solver--solver-valid-p record))))
                      all-records))
         (optional-invalid
          (seq-filter (lambda (record)
                        (and (my/lifeos-solver--active-record-p record)
                             (not (gethash (plist-get record :id) mandatory-ids))
                             (not (my/lifeos-solver--solver-valid-p record))))
                      all-records))
           (optional-waiting
           (seq-filter (lambda (record)
                         (and (equal (plist-get record :state) "WAITING")
                              (not (gethash (plist-get record :id) mandatory-ids))
                              (not (my/lifeos-solver--wait-release-minute record now))))
                        all-records))
          (week-start (my/lifeos--current-week-start))
          (configuration-result (my/lifeos-solver--configuration week-start))
          (configuration (plist-get configuration-result :values))
         (horizon-start-minute (my/lifeos-solver--quantum-at-or-after now))
         (horizon-start (seconds-to-time (* horizon-start-minute 60)))
          (furthest-deadline
           (seq-reduce
            (lambda (latest record)
              (let* ((deadline (my/lifeos--record-deadline-end record))
                    (scheduled (my/lifeos--record-scheduled-time record))
                    (fixed-end
                     (and scheduled
                          (time-add scheduled
                                    (seconds-to-time
                                     (* 60 (or (plist-get record :minutes) 0)))))))
               (dolist (candidate (delq nil (list deadline fixed-end)) latest)
                 (when (time-less-p latest candidate)
                   (setq latest candidate)))))
            (append records (plist-get analysis :projects))
           (my/lifeos--date-time (my/lifeos--date-add-days week-start 28) "00:00")))
         (horizon-end (time-add furthest-deadline (seconds-to-time 60)))
         (days (max 1 (ceiling (/ (float-time (time-subtract horizon-end horizon-start))
                                  (* 24 60 60.0)))))
         (weeks (ceiling days 7))
         (availability (my/lifeos-solver--canonical-availability
                         (my/lifeos--forecast-availability week-start weeks)))
           (calendar (my/lifeos-solver--calendar-blocks
                      horizon-start horizon-end configuration source-markers))
           (current-plan-busy
            (my/lifeos-schedule-current-plan-busy
             horizon-start-minute (my/lifeos-solver--minute horizon-end)))
           (sleep (my/lifeos-solver--sleep-blocks
                   horizon-start horizon-end (plist-get configuration :sleep)))
           (reserve (my/lifeos-solver--reserve-blocks
                     horizon-start horizon-end availability configuration))
           (stress (my/lifeos-solver--stress-profiles
                    records availability (car calendar) configuration))
           (projects (my/lifeos-solver--projects-json
                       (plist-get analysis :projects)))
           (intentions (my/lifeos-solver--intentions
                         week-start records (plist-get analysis :projects)
                         source-markers))
           (calendar-coverage (my/lifeos-solver--calendar-coverage now horizon-end))
           (hard-issues (append
                            (plist-get configuration-result :issues)
                            (and (plist-get configuration-result :issues)
                                 (list
                                  (format "Repair %s through M-x my/lifeos-settings; choose the matching recurring or weekly policy source."
                                          (plist-get configuration-result
                                                     :source-id))))
                            (plist-get intentions :issues)
                          (my/lifeos-solver--ungroomed-mandatory-issues all-records)
                          (mapcar (lambda (record)
                                  (format "Mandatory task %s is invalid or non-executable."
                                          (my/lifeos-solver--source-id record "task")))
                                mandatory-invalid)
                           (my/lifeos-solver--mandatory-graph-issues
                            analysis mandatory-ids)
                           (mapcar
                            (lambda (project)
                              (format "Committed project source %s has no stable ID and cannot be modeled."
                                      (my/lifeos-solver--source-id project "project")))
                            (seq-filter
                             (lambda (project)
                               (and (eq (plist-get project :commitment) 'committed)
                                    (not (plist-get project :id))))
                             (plist-get analysis :projects)))
                          (cadr calendar)
                          (cadr calendar-coverage)
                          (cdr sleep)
                          (unless (plist-get configuration :sleep)
                            '("Nightly sleep envelope and minimum are not configured."))))
          (safety-issues
            (append
             (when (null (plist-get configuration :default-safety-buffer))
               '("Default deadline safety buffer is not configured."))
              (when (or (null (plist-get configuration :daily-reserve))
                        (null (plist-get configuration :weekly-reserve))
                        (null (plist-get configuration :reserve-block)))
                '("Distributed reserve policy is not fully configured."))
             (cdr projects)
             (cdr reserve)))
         (completed-prerequisites
          (seq-some
           (lambda (record)
             (seq-some
              (lambda (target)
                (when-let* ((target-record
                             (seq-find (lambda (candidate)
                                         (equal (plist-get candidate :id) target))
                                       all-records)))
                  (member (plist-get target-record :state) '("DONE" "CANCELLED"))))
              (plist-get record :targets)))
           records))
         (input-assumptions
          (append
           (list
             "Planning begins at the first 15-minute quantum at or after normalization time; elapsed time is excluded."
              "Current-week intention windows retain the full calendar week for actual-versus-target accounting."
              "Matching intention selectors count only timed calendar event minutes in the intention window; all-day events, travel, and remote setup are never credited."
             "Remaining task durations are rounded to the 15-minute scheduling quantum."
             (format "Solver configuration source: %s."
                     (plist-get configuration-result :source-id))
             "Availability is generated from current-week rules through the normalized horizon; time outside those windows is unavailable.")
             (cddr calendar)
             (nth 2 calendar-coverage)
              (cdr stress)
              (plist-get intentions :assumptions)
           (when completed-prerequisites
             '("Completed or cancelled prerequisites are treated as satisfied and are not serialized."))
           (when optional-waiting
             (list (format "%d unresolved optional WAITING task(s) were omitted from solver candidates."
                           (length optional-waiting))))
            (when optional-invalid
              (list (format "%d invalid optional active task(s) were omitted; they do not block mandatory assurance."
                            (length optional-invalid)))))))
    (my/lifeos-solver--capture-source-markers
     (append all-records
              (plist-get analysis :orphan-records))
     (plist-get analysis :projects) source-markers)
    `((protocolVersion . ,my/lifeos-solver-protocol-version)
       (requestId . ,(format "emacs-%d" (cl-incf my/lifeos-solver-request-sequence)))
       (horizon . ((start . ,horizon-start-minute)
                   (end . ,(my/lifeos-solver--minute horizon-end))))
      (schedulingQuantumMinutes . 15)
      (timeoutMs . ,my/lifeos-solver-timeout-milliseconds)
       (calendarCoverageEnd . ,(car calendar-coverage))
      (availabilityCoverageEnd . ,(my/lifeos-solver--minute horizon-end))
       (defaultSafetyBufferMinutes . ,(or (plist-get configuration :default-safety-buffer) 0))
       (hardIssues . ,(vconcat hard-issues))
       (safetyIssues . ,(vconcat safety-issues))
       (inputAssumptions . ,(vconcat input-assumptions))
         (tasks . ,(vconcat
                    (append
                     (mapcar (lambda (record)
                               (my/lifeos-solver--task-json
                                record task-ids mandatory-ids now))
                             records)
                     (append (my/lifeos-solver--virtual-tasks-json
                              (plist-get analysis :projects)) nil))))
       (projects . ,(car projects))
      (availability . ,availability)
       (busy . ,(vconcat (append (car calendar) nil)
                         (append current-plan-busy nil)))
        (sleep . ,(or (car sleep) []))
       (reserve . ,(car reserve))
       (intentions . ,(plist-get intentions :intentions))
       (stressProfiles . ,(car stress))
       (scenario . ,(or scenario :null))
       (candidate . :null)
       (negotiationQueries . ,(vconcat negotiation-queries)))))

(defun my/lifeos-solver--request-id-member-p (request collection id)
  "Return non-nil when ID occurs in REQUEST COLLECTION."
  (seq-some (lambda (item) (equal (alist-get 'id item) id))
            (append (alist-get collection request) nil)))

(defun my/lifeos-solver--validate-minute-range (request start end label)
  "Validate START through END against REQUEST for LABEL."
  (let ((horizon (alist-get 'horizon request))
        (quantum (alist-get 'schedulingQuantumMinutes request)))
    (unless (and (integerp start) (integerp end) (< start end))
      (user-error "%s must have an end after its start" label))
    (unless (and (<= (alist-get 'start horizon) start)
                 (<= end (alist-get 'end horizon)))
      (user-error "%s must fit inside the planning horizon" label))
    (unless (= (% (- end start) quantum) 0)
      (user-error "%s duration must align to %d minutes" label quantum))))

(defun my/lifeos-solver-scenario-reserve (request start end &optional id scenario)
  "Return SCENARIO with a read-only reservation from START through END."
  (my/lifeos-solver--validate-minute-range request start end "Reservation")
  (let* ((scenario (copy-tree (or scenario
                                  (my/lifeos-solver--empty-scenario
                                   "interactive-scenario"))))
         (id (or id "interactive-reservation"))
         (reservations (append (alist-get 'reservations scenario) nil)))
    (when (or (my/lifeos-solver--request-id-member-p request 'busy id)
              (seq-some (lambda (item) (equal (alist-get 'id item) id)) reservations))
      (user-error "Reservation ID already exists: %s" id))
    (setf (alist-get 'reservations scenario)
          (vconcat reservations
                   (list `((id . ,id) (start . ,start) (end . ,end)
                           (kind . "scenario-reservation")))))
    scenario))

(defun my/lifeos-solver-scenario-estimate-change
    (request task-id duration-minutes &optional scenario)
  "Return SCENARIO changing TASK-ID to DURATION-MINUTES."
  (unless (my/lifeos-solver--request-id-member-p request 'tasks task-id)
    (user-error "Unknown solver task: %s" task-id))
  (unless (and (integerp duration-minutes) (> duration-minutes 0)
               (= (% duration-minutes
                     (alist-get 'schedulingQuantumMinutes request)) 0))
    (user-error "Estimate must be positive and quantum-aligned"))
  (let* ((scenario (copy-tree (or scenario
                                  (my/lifeos-solver--empty-scenario
                                   "interactive-scenario"))))
         (changes (append (alist-get 'estimateChanges scenario) nil)))
    (when (seq-some (lambda (item) (equal (alist-get 'taskId item) task-id)) changes)
      (user-error "Scenario already changes task %s" task-id))
    (setf (alist-get 'estimateChanges scenario)
          (vconcat changes
                   (list `((taskId . ,task-id)
                           (durationMinutes . ,duration-minutes)))))
    scenario))

(defun my/lifeos-solver-scenario-intention-bounds
    (request intention-id minimum target maximum &optional scenario)
  "Return SCENARIO changing INTENTION-ID bounds.
MINIMUM, TARGET, and MAXIMUM are minutes or nil."
  (unless (my/lifeos-solver--request-id-member-p request 'intentions intention-id)
    (user-error "Unknown solver intention: %s" intention-id))
  (dolist (value (list minimum target maximum))
    (unless (or (null value) (and (integerp value) (>= value 0)))
      (user-error "Intention bounds must be non-negative minutes or nil")))
  (when (and minimum maximum (> minimum maximum))
    (user-error "Intention minimum exceeds maximum"))
  (when (and target minimum (< target minimum))
    (user-error "Intention target is below minimum"))
  (when (and target maximum (> target maximum))
    (user-error "Intention target exceeds maximum"))
  (let* ((scenario (copy-tree (or scenario
                                  (my/lifeos-solver--empty-scenario
                                   "interactive-scenario"))))
         (changes (append (alist-get 'intentionChanges scenario) nil)))
    (when (seq-some (lambda (item)
                      (equal (alist-get 'intentionId item) intention-id))
                    changes)
      (user-error "Scenario already changes intention %s" intention-id))
    (setf (alist-get 'intentionChanges scenario)
          (vconcat changes
                   (list `((intentionId . ,intention-id)
                           (minimumMinutes . ,(or minimum :null))
                           (targetMinutes . ,(or target :null))
                           (maximumMinutes . ,(or maximum :null))))))
    scenario))

(defun my/lifeos-solver-scenario-unlock (request task-id &optional scenario)
  "Return SCENARIO unlocking fixed commitment TASK-ID."
  (let ((task (seq-find (lambda (item) (equal (alist-get 'id item) task-id))
                        (append (alist-get 'tasks request) nil))))
    (unless (and task (numberp (alist-get 'fixedStart task)))
      (user-error "Unlock target must be a fixed-start task: %s" task-id)))
  (let* ((scenario (copy-tree (or scenario
                                  (my/lifeos-solver--empty-scenario
                                   "interactive-scenario"))))
         (ids (append (alist-get 'unlockedCommitmentIds scenario) nil)))
    (when (member task-id ids)
      (user-error "Scenario already unlocks %s" task-id))
    (setf (alist-get 'unlockedCommitmentIds scenario)
          (vconcat ids (list task-id)))
    scenario))

(defun my/lifeos-solver-scenario-project-change
    (request project-id change &optional scenario)
  "Return SCENARIO with CHANGE overlaid on PROJECT-ID without writing Org."
  (unless (my/lifeos-solver--request-id-member-p request 'projects project-id)
    (user-error "Unknown solver project: %s" project-id))
  (unless (and (listp change) change)
    (user-error "Project scenario change cannot be empty"))
  (let ((quantum (alist-get 'schedulingQuantumMinutes request))
        (allowed '(projectEffortMinutes deadline commitment defaultWorkMode
                                          planningChunkMinutes estimateConfidence)))
    (dolist (entry change)
      (unless (memq (car entry) allowed)
        (user-error "Unknown project scenario field: %s" (car entry))))
    (dolist (field '(projectEffortMinutes planningChunkMinutes))
      (when-let* ((entry (assq field change)))
        (unless (and (integerp (cdr entry)) (> (cdr entry) 0)
                     (= (% (cdr entry) quantum) 0))
          (user-error "%s must be positive and quantum-aligned" field))))
    (when-let* ((entry (assq 'deadline change)))
      (unless (integerp (cdr entry)) (user-error "Project deadline must be a minute")))
    (when-let* ((entry (assq 'commitment change)))
      (unless (member (cdr entry) '("COMMITTED" "UNCOMMITTED"))
        (user-error "Project commitment must be COMMITTED or UNCOMMITTED")))
    (when-let* ((entry (assq 'defaultWorkMode change)))
      (unless (and (stringp (cdr entry)) (not (string-empty-p (cdr entry))))
        (user-error "Project work mode cannot be empty")))
    (when-let* ((entry (assq 'estimateConfidence change)))
      (unless (member (cdr entry) my/lifeos-estimate-confidence-values)
        (user-error "Estimate confidence must be Low, Medium, or High"))))
  (let* ((scenario (copy-tree (or scenario
                                  (my/lifeos-solver--empty-scenario
                                   "interactive-scenario"))))
         (changes (append (alist-get 'projectChanges scenario) nil))
         (existing (seq-find (lambda (item)
                               (equal (alist-get 'projectId item) project-id))
                             changes)))
    (if existing
        (setcdr existing (append (copy-tree change) (cdr existing)))
      (setq changes (append changes (list (cons (cons 'projectId project-id)
                                                (copy-tree change))))))
    (setf (alist-get 'projectChanges scenario) (vconcat changes))
    scenario))

(defun my/lifeos-solver--validate-project-query-input
    (request project-id &optional assurance)
  "Validate PROJECT-ID and optional ASSURANCE for REQUEST."
  (unless (my/lifeos-solver--request-id-member-p request 'projects project-id)
    (user-error "Unknown solver project: %s" project-id))
  (when (and assurance (not (member assurance '("deadline-only" "safe"))))
    (user-error "Assurance must be deadline-only or safe")))

(defun my/lifeos-solver-negotiation-query
    (request kind id scope &rest properties)
  "Build and validate a negotiation query for REQUEST.
KIND, ID, SCOPE, and PROPERTIES use the discriminated protocol schema."
  (unless (member kind '("maximum-deadline-only-discretionary-duration"
                         "maximum-safe-discretionary-duration"
                         "minimum-required-work-in-window"
                         "latest-safe-discretionary-start"
                         "minimal-commitment-unlock-set"
                         "maximum-project-effort"
                         "minimum-project-work-in-window"
                         "latest-safe-project-start"
                         "earliest-feasible-project-deadline"
                         "minimal-project-defer-set"))
    (user-error "Unknown negotiation kind: %s" kind))
  (unless (member scope '("baseline" "scenario"))
    (user-error "Negotiation scope must be baseline or scenario"))
  (when (and (equal scope "scenario")
             (memq (alist-get 'scenario request) '(nil :null)))
    (user-error "Scenario negotiation requires a scenario"))
  (let ((query `((id . ,id) (kind . ,kind) (scope . ,scope))))
    (pcase kind
      ((or "maximum-deadline-only-discretionary-duration"
           "maximum-safe-discretionary-duration")
       (let ((start (plist-get properties :start))
             (end (plist-get properties :maximum-end)))
         (my/lifeos-solver--validate-minute-range request start end "Query interval")
         (setq query (append query `((start . ,start) (maximumEnd . ,end))))))
      ("minimum-required-work-in-window"
       (let ((start (plist-get properties :start))
             (end (plist-get properties :end))
             (assurance (plist-get properties :assurance)))
         (my/lifeos-solver--validate-minute-range request start end "Query interval")
         (unless (member assurance '("deadline-only" "safe"))
           (user-error "Assurance must be deadline-only or safe"))
         (setq query (append query `((start . ,start) (end . ,end)
                                     (assurance . ,assurance))))))
      ("latest-safe-discretionary-start"
       (let ((duration (plist-get properties :duration-minutes))
             (start (plist-get properties :earliest-start))
             (end (plist-get properties :latest-end)))
         (my/lifeos-solver--validate-minute-range request start end "Query interval")
         (unless (and (integerp duration) (> duration 0)
                      (= (% duration
                            (alist-get 'schedulingQuantumMinutes request)) 0)
                      (<= duration (- end start)))
           (user-error "Duration must be positive, aligned, and fit the interval"))
         (setq query (append query `((durationMinutes . ,duration)
                                     (earliestStart . ,start)
                                     (latestEnd . ,end))))))
      ("minimal-commitment-unlock-set"
       (let ((ids (plist-get properties :candidate-commitment-ids))
             (assurance (plist-get properties :assurance)))
         (unless (and ids (= (length ids) (length (delete-dups (copy-sequence ids)))))
           (user-error "Choose one or more unique commitment candidates"))
         (dolist (task-id ids)
           (let ((task (seq-find
                        (lambda (item) (equal (alist-get 'id item) task-id))
                        (append (alist-get 'tasks request) nil))))
             (unless (and task (numberp (alist-get 'fixedStart task)))
               (user-error "Unlock candidate is not fixed: %s" task-id))))
         (unless (member assurance '("deadline-only" "safe"))
           (user-error "Assurance must be deadline-only or safe"))
          (setq query
                (append query `((candidateCommitmentIds . ,(vconcat ids))
                                (assurance . ,assurance))))))
      ("maximum-project-effort"
       (let ((project-id (plist-get properties :project-id))
             (maximum (plist-get properties :maximum-effort-minutes))
             (assurance (plist-get properties :assurance)))
         (my/lifeos-solver--validate-project-query-input
          request project-id assurance)
         (unless (and (integerp maximum) (> maximum 0)
                      (= (% maximum (alist-get 'schedulingQuantumMinutes request)) 0))
           (user-error "Maximum effort must be positive and quantum-aligned"))
         (setq query (append query `((projectId . ,project-id)
                                     (maximumEffortMinutes . ,maximum)
                                     (assurance . ,assurance))))))
      ("minimum-project-work-in-window"
       (let ((project-id (plist-get properties :project-id))
             (start (plist-get properties :start))
             (end (plist-get properties :end))
             (assurance (plist-get properties :assurance)))
         (my/lifeos-solver--validate-project-query-input
          request project-id assurance)
         (my/lifeos-solver--validate-minute-range request start end "Project work window")
         (setq query (append query `((projectId . ,project-id) (start . ,start)
                                     (end . ,end) (assurance . ,assurance))))))
      ("latest-safe-project-start"
       (let ((project-id (plist-get properties :project-id))
             (start (plist-get properties :earliest-start))
             (latest (plist-get properties :latest-start))
             (quantum (alist-get 'schedulingQuantumMinutes request)))
         (my/lifeos-solver--validate-project-query-input request project-id nil)
         (my/lifeos-solver--validate-minute-range
          request start (+ latest quantum) "Project start search")
         (setq query (append query `((projectId . ,project-id)
                                     (earliestStart . ,start)
                                     (latestStart . ,latest))))))
      ("earliest-feasible-project-deadline"
       (let ((project-id (plist-get properties :project-id))
             (earliest (plist-get properties :earliest-deadline))
             (latest (plist-get properties :latest-deadline))
             (assurance (plist-get properties :assurance))
             (quantum (alist-get 'schedulingQuantumMinutes request)))
         (my/lifeos-solver--validate-project-query-input
          request project-id assurance)
         (my/lifeos-solver--validate-minute-range
          request (- earliest quantum) latest "Project deadline search")
         (setq query (append query `((projectId . ,project-id)
                                     (earliestDeadline . ,earliest)
                                     (latestDeadline . ,latest)
                                     (assurance . ,assurance))))))
      ("minimal-project-defer-set"
       (let ((ids (plist-get properties :candidate-project-ids))
             (assurance (plist-get properties :assurance)))
         (unless (and ids (= (length ids) (length (delete-dups (copy-sequence ids)))))
           (user-error "Choose one or more unique project candidates"))
         (dolist (project-id ids)
           (my/lifeos-solver--validate-project-query-input request project-id nil))
         (unless (member assurance '("deadline-only" "safe"))
           (user-error "Assurance must be deadline-only or safe"))
          (setq query (append query `((candidateProjectIds . ,(vconcat ids))
                                      (assurance . ,assurance)))))))
    query))

(defun my/lifeos-solver--default-command ()
  "Return the repository-local solver command."
  (let* ((origin (or my/lifeos-solver-module-file
                     load-file-name
                     (locate-library "lifeos-solver")
                     buffer-file-name))
         (root (and origin (locate-dominating-file origin "lifeos-solver/package.json"))))
    (unless root
      (error "Cannot locate lifeos-solver/package.json"))
    (list "npm" "--prefix" (expand-file-name "lifeos-solver" root)
          "run" "--silent" "solve")))

(defun my/lifeos-solver--cancel-process ()
  "Cancel the current shadow process and timeout timer."
  (when (processp my/lifeos-solver-process)
    (my/lifeos-solver--cancel-process-timer my/lifeos-solver-process)
    (when (process-live-p my/lifeos-solver-process)
      (delete-process my/lifeos-solver-process))))

(defun my/lifeos-solver--cancel-process-timer (process)
  "Cancel PROCESS's own timer without disturbing a newer request."
  (let ((timer (process-get process 'lifeos-timer)))
    (when (timerp timer)
      (cancel-timer timer))
    (process-put process 'lifeos-timer nil)
    (when (eq timer my/lifeos-solver-process-timer)
      (setq my/lifeos-solver-process-timer nil))))

(defun my/lifeos-solver--process-timeout (process request-id)
  "Stop PROCESS for REQUEST-ID without discarding the last good result."
  (when (and (equal request-id my/lifeos-solver-current-request-id)
              (process-live-p process))
    (setq my/lifeos-solver-last-error "Solver process timed out"
          my/lifeos-solver-last-request-context
          (process-get process 'lifeos-context))
    (process-put process 'lifeos-timed-out t)
    (delete-process process)))

(defun my/lifeos-solver--current-response-p (response request-id)
  "Return non-nil when RESPONSE is successful and current for REQUEST-ID."
  (and (equal request-id my/lifeos-solver-current-request-id)
       (null (my/lifeos-solver--response-validation-error response request-id))
       (equal (alist-get 'requestId response) request-id)
       (equal (alist-get 'status response) "ok")))

(defun my/lifeos-solver--json-object-p (value)
  "Return non-nil when VALUE is a nonempty parsed JSON object."
  (and (consp value) (seq-every-p #'consp value)))

(defun my/lifeos-solver--required-fields-p (object fields)
  "Return non-nil when parsed JSON OBJECT contains every member of FIELDS."
  (seq-every-p (lambda (field) (assq field object)) fields))

(defun my/lifeos-solver--string-list-p (value)
  "Return non-nil when VALUE is a parsed JSON array of strings."
  (and (listp value) (seq-every-p #'stringp value)))

(defun my/lifeos-solver--nullable-integer-p (value)
  "Return non-nil when VALUE is nil or an integer."
  (or (null value) (integerp value)))

(defun my/lifeos-solver--placement-valid-p (placement)
  "Return non-nil when PLACEMENT has the response placement shape."
  (and (my/lifeos-solver--json-object-p placement)
       (my/lifeos-solver--required-fields-p
        placement '(taskId projectId start end kind))
       (stringp (alist-get 'taskId placement))
       (or (null (alist-get 'projectId placement))
           (stringp (alist-get 'projectId placement)))
       (integerp (alist-get 'start placement))
       (integerp (alist-get 'end placement))
       (< (alist-get 'start placement) (alist-get 'end placement))
       (member (alist-get 'kind placement) '("fixed" "proposed"))))

(defun my/lifeos-solver--timed-result-valid-p (item)
  "Return non-nil when ITEM is an ID/start/end response object."
  (and (my/lifeos-solver--json-object-p item)
       (my/lifeos-solver--required-fields-p item '(id start end))
       (stringp (alist-get 'id item))
       (integerp (alist-get 'start item))
       (integerp (alist-get 'end item))
       (< (alist-get 'start item) (alist-get 'end item))))

(defun my/lifeos-solver--solve-result-validation-error (result label)
  "Return a structural validation error for solve RESULT named LABEL."
  (cond
   ((not (my/lifeos-solver--json-object-p result))
    (format "%s result is not an object" label))
   ((not (my/lifeos-solver--required-fields-p
          result '(feasibility safety resilience placements reservePlacements
                                sleepPlacements intentions deadlineMargins
                                conflicts assumptions
                                unlockedCommitmentIds stressResults)))
    (format "%s result is missing required fields" label))
   ((not (member (alist-get 'feasibility result)
                 '("PROVEN FEASIBLE" "PROVEN INFEASIBLE" "UNKNOWN")))
    (format "%s result has invalid feasibility" label))
   ((not (member (alist-get 'safety result) '(nil "SAFE" "TIGHT")))
    (format "%s result has invalid safety" label))
   ((not (member (alist-get 'resilience result) '(nil "RESILIENT" "FRAGILE")))
    (format "%s result has invalid resilience" label))
   ((not (and (listp (alist-get 'placements result))
              (seq-every-p #'my/lifeos-solver--placement-valid-p
                           (alist-get 'placements result))))
    (format "%s result has malformed task placements" label))
   ((not (and (listp (alist-get 'reservePlacements result))
              (seq-every-p #'my/lifeos-solver--timed-result-valid-p
                           (alist-get 'reservePlacements result))))
    (format "%s result has malformed reserve placements" label))
   ((not (and (listp (alist-get 'sleepPlacements result))
              (seq-every-p #'my/lifeos-solver--timed-result-valid-p
                           (alist-get 'sleepPlacements result))))
    (format "%s result has malformed sleep placements" label))
    ((not (and (listp (alist-get 'intentions result))
              (seq-every-p
               (lambda (item)
                 (and (my/lifeos-solver--json-object-p item)
                      (my/lifeos-solver--required-fields-p
                       item '(id allocatedMinutes minimumShortfallMinutes
                                 targetDeviationMinutes maximumExcessMinutes))
                      (stringp (alist-get 'id item))
                      (seq-every-p
                       (lambda (field)
                         (let ((value (alist-get field item)))
                           (and (integerp value) (>= value 0))))
                       '(allocatedMinutes minimumShortfallMinutes
                         targetDeviationMinutes maximumExcessMinutes))))
               (alist-get 'intentions result))))
    (format "%s result has malformed intention outcomes" label))
    ((not (and
           (listp (alist-get 'deadlineMargins result))
           (seq-every-p
            (lambda (item)
              (and (my/lifeos-solver--json-object-p item)
                   (my/lifeos-solver--required-fields-p
                    item '(taskId projectId deadline completionTime
                                  hardDeadlineMarginMinutes safetyBufferMinutes
                                  safetyMarginMinutes))
                   (stringp (alist-get 'taskId item))
                   (or (null (alist-get 'projectId item))
                       (stringp (alist-get 'projectId item)))
                   (seq-every-p (lambda (field) (integerp (alist-get field item)))
                                '(deadline completionTime hardDeadlineMarginMinutes
                                  safetyBufferMinutes safetyMarginMinutes))
                   (>= (alist-get 'safetyBufferMinutes item) 0)))
            (alist-get 'deadlineMargins result))))
     (format "%s result has malformed deadline margins" label))
    ((not (and (listp (alist-get 'conflicts result))
              (seq-every-p
               (lambda (item)
                 (and (my/lifeos-solver--json-object-p item)
                       (my/lifeos-solver--required-fields-p
                        item '(constraintId sourceId kind message taskIds
                                            projectIds shared))
                       (seq-every-p (lambda (field) (stringp (alist-get field item)))
                                    '(constraintId sourceId kind message))
                       (my/lifeos-solver--string-list-p (alist-get 'taskIds item))
                       (my/lifeos-solver--string-list-p (alist-get 'projectIds item))
                       (memq (alist-get 'shared item) '(t nil))
                       (or (not (assq 'relaxation item))
                           (let ((relaxation (alist-get 'relaxation item)))
                             (and (my/lifeos-solver--json-object-p relaxation)
                                  (my/lifeos-solver--required-fields-p
                                   relaxation '(type text))
                                  (stringp (alist-get 'type relaxation))
                                  (stringp (alist-get 'text relaxation)))))))
                (alist-get 'conflicts result))))
    (format "%s result has malformed conflicts" label))
   ((not (my/lifeos-solver--string-list-p (alist-get 'assumptions result)))
    (format "%s result has malformed assumptions" label))
   ((not (my/lifeos-solver--string-list-p
          (alist-get 'unlockedCommitmentIds result)))
    (format "%s result has malformed unlocked commitments" label))
   ((not (and (listp (alist-get 'stressResults result))
              (seq-every-p
               (lambda (item)
                 (and (my/lifeos-solver--json-object-p item)
                      (my/lifeos-solver--required-fields-p item '(id feasibility))
                      (stringp (alist-get 'id item))
                      (member (alist-get 'feasibility item)
                              '("PROVEN FEASIBLE" "PROVEN INFEASIBLE" "UNKNOWN"))))
               (alist-get 'stressResults result))))
    (format "%s result has malformed stress results" label))))

(defun my/lifeos-solver--negotiation-result-valid-p (item)
  "Return non-nil when discriminated negotiation result ITEM is valid."
  (and (my/lifeos-solver--json-object-p item)
       (my/lifeos-solver--required-fields-p
        item '(id kind scope feasibility assumptions))
       (stringp (alist-get 'id item))
       (member (alist-get 'scope item) '("baseline" "scenario"))
       (member (alist-get 'feasibility item)
               '("PROVEN FEASIBLE" "PROVEN INFEASIBLE" "UNKNOWN"))
       (my/lifeos-solver--string-list-p (alist-get 'assumptions item))
       (pcase (alist-get 'kind item)
         ((or "maximum-deadline-only-discretionary-duration"
              "maximum-safe-discretionary-duration")
          (and (my/lifeos-solver--required-fields-p
                item '(maximumDurationMinutes testedStart testedMaximumEnd))
               (or (null (alist-get 'maximumDurationMinutes item))
                   (and (integerp (alist-get 'maximumDurationMinutes item))
                        (>= (alist-get 'maximumDurationMinutes item) 0)))
               (integerp (alist-get 'testedStart item))
               (integerp (alist-get 'testedMaximumEnd item))))
          ((or "minimum-required-work-in-window" "minimum-project-work-in-window")
           (and (my/lifeos-solver--required-fields-p
                 item '(assurance minimumRequiredMinutes testedStart testedEnd))
                (or (not (equal (alist-get 'kind item)
                                "minimum-project-work-in-window"))
                    (stringp (alist-get 'projectId item)))
               (member (alist-get 'assurance item) '("deadline-only" "safe"))
               (or (null (alist-get 'minimumRequiredMinutes item))
                   (and (integerp (alist-get 'minimumRequiredMinutes item))
                        (>= (alist-get 'minimumRequiredMinutes item) 0)))
               (integerp (alist-get 'testedStart item))
               (integerp (alist-get 'testedEnd item))))
         ("latest-safe-discretionary-start"
          (and (my/lifeos-solver--required-fields-p
                item '(latestStart testedDurationMinutes testedEarliestStart
                                   testedLatestEnd))
               (or (null (alist-get 'latestStart item))
                   (integerp (alist-get 'latestStart item)))
               (integerp (alist-get 'testedDurationMinutes item))
               (> (alist-get 'testedDurationMinutes item) 0)
               (integerp (alist-get 'testedEarliestStart item))
               (integerp (alist-get 'testedLatestEnd item))))
          ("minimal-commitment-unlock-set"
          (and (my/lifeos-solver--required-fields-p
                item '(assurance candidateCommitmentIds unlockedCommitmentIds))
               (member (alist-get 'assurance item) '("deadline-only" "safe"))
               (my/lifeos-solver--string-list-p
                (alist-get 'candidateCommitmentIds item))
               (or (null (alist-get 'unlockedCommitmentIds item))
                   (my/lifeos-solver--string-list-p
                     (alist-get 'unlockedCommitmentIds item)))))
          ("maximum-project-effort"
           (and (my/lifeos-solver--required-fields-p
                 item '(projectId assurance maximumEffortMinutes
                                  testedMaximumEffortMinutes))
                (stringp (alist-get 'projectId item))
                (member (alist-get 'assurance item) '("deadline-only" "safe"))
                (my/lifeos-solver--nullable-integer-p
                 (alist-get 'maximumEffortMinutes item))
                (integerp (alist-get 'testedMaximumEffortMinutes item))))
          ("latest-safe-project-start"
           (and (my/lifeos-solver--required-fields-p
                 item '(projectId latestStart testedEarliestStart testedLatestStart))
                (stringp (alist-get 'projectId item))
                (my/lifeos-solver--nullable-integer-p (alist-get 'latestStart item))
                (integerp (alist-get 'testedEarliestStart item))
                (integerp (alist-get 'testedLatestStart item))))
          ("earliest-feasible-project-deadline"
           (and (my/lifeos-solver--required-fields-p
                 item '(projectId assurance earliestDeadline
                                  testedEarliestDeadline testedLatestDeadline))
                (stringp (alist-get 'projectId item))
                (member (alist-get 'assurance item) '("deadline-only" "safe"))
                (my/lifeos-solver--nullable-integer-p
                 (alist-get 'earliestDeadline item))
                (integerp (alist-get 'testedEarliestDeadline item))
                (integerp (alist-get 'testedLatestDeadline item))))
          ("minimal-project-defer-set"
           (and (my/lifeos-solver--required-fields-p
                 item '(assurance candidateProjectIds deferredProjectIds
                                  conflictProjectIds))
                (member (alist-get 'assurance item) '("deadline-only" "safe"))
                (my/lifeos-solver--string-list-p (alist-get 'candidateProjectIds item))
                (or (null (alist-get 'deferredProjectIds item))
                    (my/lifeos-solver--string-list-p
                     (alist-get 'deferredProjectIds item)))
                (my/lifeos-solver--string-list-p
                 (alist-get 'conflictProjectIds item))))
          (_ nil))))

(defun my/lifeos-solver--project-result-validation-error (result label)
  "Return a validation error for project RESULT named LABEL."
  (cond
   ((not (my/lifeos-solver--json-object-p result))
    (format "%s is not an object" label))
   ((not (my/lifeos-solver--required-fields-p
          result '(projectId definitionStatus commitment isolatedFeasibility
                             proofKind isolatedResult borrowedPrerequisiteTaskIds
                             borrowedPrerequisiteProjectIds portfolioStatus
                             hardDeadlineMarginMinutes safetyMarginMinutes
                             conflictTaskIds conflictProjectIds)))
    (format "%s is missing required fields" label))
   ((not (and (stringp (alist-get 'projectId result))
              (member (alist-get 'definitionStatus result)
                      '("INCOMPLETE" "COARSE" "DETAILED"))
              (member (alist-get 'commitment result) '("COMMITTED" "UNCOMMITTED"))
              (member (alist-get 'isolatedFeasibility result)
                      '("FEASIBLE" "INFEASIBLE" "UNKNOWN" "UNCOMMITTED"))
              (member (alist-get 'proofKind result)
                      '(nil "CAPACITY FEASIBLE" "STRUCTURALLY FEASIBLE"))
              (member (alist-get 'portfolioStatus result)
                      '("FITS" "TIGHT" "CONFLICT-INVOLVED" "UNKNOWN"
                               "UNCOMMITTED"))
              (my/lifeos-solver--nullable-integer-p
               (alist-get 'hardDeadlineMarginMinutes result))
              (my/lifeos-solver--nullable-integer-p
               (alist-get 'safetyMarginMinutes result))
              (seq-every-p
               (lambda (field)
                 (my/lifeos-solver--string-list-p (alist-get field result)))
               '(borrowedPrerequisiteTaskIds borrowedPrerequisiteProjectIds
                 conflictTaskIds conflictProjectIds))))
    (format "%s has malformed project fields" label))
   ((and (alist-get 'isolatedResult result)
         (my/lifeos-solver--solve-result-validation-error
          (alist-get 'isolatedResult result) (concat label " isolated result"))))))

(defun my/lifeos-solver--portfolio-validation-error (portfolio label)
  "Return a validation error for PORTFOLIO named LABEL."
  (cond
   ((not (my/lifeos-solver--json-object-p portfolio))
    (format "%s is not an object" label))
   ((not (my/lifeos-solver--required-fields-p
          portfolio '(definitionStatus feasibility safety modeledProjectIds
                                      excludedProjectIds modeledSubset globalResult
                                      projectResults)))
    (format "%s is missing required fields" label))
   ((not (and (member (alist-get 'definitionStatus portfolio)
                      '("COMPLETE" "INCOMPLETE"))
              (member (alist-get 'feasibility portfolio)
                      '("PROVEN FEASIBLE" "PROVEN INFEASIBLE" "UNKNOWN"))
              (member (alist-get 'safety portfolio) '(nil "SAFE" "TIGHT"))
              (my/lifeos-solver--string-list-p
               (alist-get 'modeledProjectIds portfolio))
              (my/lifeos-solver--string-list-p
               (alist-get 'excludedProjectIds portfolio))
              (memq (alist-get 'modeledSubset portfolio) '(t nil))))
    (format "%s has malformed fields" label))
   ((my/lifeos-solver--solve-result-validation-error
     (alist-get 'globalResult portfolio) (concat label " global result")))
   ((not (and (listp (alist-get 'projectResults portfolio))
              (not (seq-some
                    (lambda (item)
                      (my/lifeos-solver--project-result-validation-error
                       item (concat label " project result")))
                    (alist-get 'projectResults portfolio)))))
    (format "%s has malformed project results" label))))

(defun my/lifeos-solver--transition-valid-p (value values)
  "Return non-nil when VALUE has baseline/scenario members from VALUES."
  (and (my/lifeos-solver--json-object-p value)
       (my/lifeos-solver--required-fields-p value '(baseline scenario))
       (member (alist-get 'baseline value) values)
       (member (alist-get 'scenario value) values)))

(defun my/lifeos-solver--comparison-validation-error (comparison)
  "Return a validation error for v2 scenario COMPARISON, or nil."
  (let ((required '(interpretation movedTaskIds addedTaskIds droppedTaskIds
                                   safetyTransition resilienceTransition
                                   taskStartDeltas intentionAllocationDeltas
                                   reservePlacementDelta stressFeasibilityTransitions
                                   projectDeltas)))
    (cond
     ((not (my/lifeos-solver--json-object-p comparison))
      "Scenario comparison is not an object")
     ((not (my/lifeos-solver--required-fields-p comparison required))
      "Scenario comparison is missing required fields")
     ((not (and (stringp (alist-get 'interpretation comparison))
                (seq-every-p
                 (lambda (field)
                   (my/lifeos-solver--string-list-p (alist-get field comparison)))
                 '(movedTaskIds addedTaskIds droppedTaskIds))
                (my/lifeos-solver--transition-valid-p
                 (alist-get 'safetyTransition comparison) '(nil "SAFE" "TIGHT"))
                (my/lifeos-solver--transition-valid-p
                 (alist-get 'resilienceTransition comparison)
                 '(nil "RESILIENT" "FRAGILE"))))
      "Scenario comparison has malformed summary fields")
     ((not (and
            (listp (alist-get 'taskStartDeltas comparison))
            (seq-every-p
             (lambda (item)
               (and (my/lifeos-solver--required-fields-p
                     item '(taskId baselineStart scenarioStart deltaMinutes))
                    (stringp (alist-get 'taskId item))
                    (seq-every-p (lambda (field) (integerp (alist-get field item)))
                                 '(baselineStart scenarioStart deltaMinutes))))
             (alist-get 'taskStartDeltas comparison))))
      "Scenario comparison has malformed task deltas")
     ((not (and
            (listp (alist-get 'intentionAllocationDeltas comparison))
            (seq-every-p
             (lambda (item)
               (and (my/lifeos-solver--required-fields-p
                     item '(intentionId baselineAllocatedMinutes
                                         scenarioAllocatedMinutes deltaMinutes))
                    (stringp (alist-get 'intentionId item))
                    (seq-every-p (lambda (field) (integerp (alist-get field item)))
                                 '(baselineAllocatedMinutes scenarioAllocatedMinutes
                                   deltaMinutes))))
             (alist-get 'intentionAllocationDeltas comparison))))
      "Scenario comparison has malformed intention deltas")
     ((not (let ((reserve (alist-get 'reservePlacementDelta comparison)))
             (and (my/lifeos-solver--required-fields-p
                   reserve '(baselineCount scenarioCount countDelta baselineMinutes
                                           scenarioMinutes minutesDelta))
                  (seq-every-p (lambda (field) (integerp (alist-get field reserve)))
                               '(baselineCount scenarioCount countDelta baselineMinutes
                                 scenarioMinutes minutesDelta)))))
      "Scenario comparison has malformed reserve delta")
     ((not (and
            (listp (alist-get 'projectDeltas comparison))
            (seq-every-p
             (lambda (item)
               (and (my/lifeos-solver--required-fields-p
                     item '(projectId baselineDefinitionStatus scenarioDefinitionStatus
                                      baselineEffortMinutes scenarioEffortMinutes
                                      effortDeltaMinutes baselineDeadline scenarioDeadline
                                      baselineCommitment scenarioCommitment
                                      baselineIsolatedFeasibility scenarioIsolatedFeasibility
                                      baselinePortfolioStatus scenarioPortfolioStatus))
                    (stringp (alist-get 'projectId item))
                    (member (alist-get 'baselineDefinitionStatus item)
                            '("INCOMPLETE" "COARSE" "DETAILED"))
                    (member (alist-get 'scenarioDefinitionStatus item)
                            '("INCOMPLETE" "COARSE" "DETAILED"))
                    (seq-every-p
                     (lambda (field)
                       (my/lifeos-solver--nullable-integer-p (alist-get field item)))
                     '(baselineEffortMinutes scenarioEffortMinutes effortDeltaMinutes
                       baselineDeadline scenarioDeadline))
                    (seq-every-p
                     (lambda (field)
                       (member (alist-get field item) '("COMMITTED" "UNCOMMITTED")))
                     '(baselineCommitment scenarioCommitment))
                    (seq-every-p
                     (lambda (field)
                       (member (alist-get field item)
                               '("FEASIBLE" "INFEASIBLE" "UNKNOWN" "UNCOMMITTED")))
                     '(baselineIsolatedFeasibility scenarioIsolatedFeasibility))
                    (seq-every-p
                     (lambda (field)
                       (member (alist-get field item)
                               '("FITS" "TIGHT" "CONFLICT-INVOLVED" "UNKNOWN"
                                        "UNCOMMITTED")))
                     '(baselinePortfolioStatus scenarioPortfolioStatus))))
             (alist-get 'projectDeltas comparison))))
      "Scenario comparison has malformed project deltas"))))

(defun my/lifeos-solver--candidate-identity-valid-p (identity)
  "Return non-nil when IDENTITY has the strict v3 candidate identity shape."
  (and (my/lifeos-solver--json-object-p identity)
       (my/lifeos-solver--required-fields-p
        identity '(candidateId revision capturedInputFingerprint normalizedRequestId))
       (stringp (alist-get 'candidateId identity))
       (integerp (alist-get 'revision identity))
       (>= (alist-get 'revision identity) 0)
       (stringp (alist-get 'capturedInputFingerprint identity))
       (stringp (alist-get 'normalizedRequestId identity))))

(defun my/lifeos-solver--response-validation-error
    (response request-id &optional expected-candidate-identity)
  "Return a protocol error for RESPONSE expected for REQUEST-ID, or nil.
EXPECTED-CANDIDATE-IDENTITY is nil for an ordinary request and an alist for a
candidate request."
  (cond
   ((not (listp response)) "Solver response is not a JSON object")
   ((not (equal (alist-get 'protocolVersion response)
                my/lifeos-solver-protocol-version))
    "Solver response protocol version does not match")
    ((not (equal (alist-get 'solverVersion response) my/lifeos-solver-version))
     "Solver response solver version does not match")
   ((not (equal (alist-get 'requestId response) request-id))
    "Solver response request ID does not match")
   ((not (assq 'candidateIdentity response))
    "Solver response has no candidate identity field")
   ((and expected-candidate-identity
         (not (my/lifeos-solver--candidate-identity-valid-p
               (alist-get 'candidateIdentity response))))
    "Solver response candidate identity is malformed")
   ((not (equal (alist-get 'candidateIdentity response)
                expected-candidate-identity))
    "Solver response candidate identity does not match")
   ((not (member (alist-get 'status response)
                 '("ok" "invalid-request" "internal-error")))
    "Solver response has an invalid status")
   ((not (assq 'errors response)) "Solver response has no errors field")
    ((not (and (listp (alist-get 'errors response))
               (seq-every-p
                (lambda (item)
                  (and (my/lifeos-solver--json-object-p item)
                       (my/lifeos-solver--required-fields-p item '(path message))
                       (stringp (alist-get 'path item))
                       (stringp (alist-get 'message item))))
                (alist-get 'errors response))))
     "Solver response errors field is malformed")
   ((and (equal (alist-get 'status response) "ok")
         (not (and (assq 'baseline response)
                   (assq 'scenario response)
                    (assq 'baselinePortfolio response)
                    (assq 'scenarioPortfolio response)
                    (assq 'comparison response)
                   (assq 'negotiationResults response))))
    "Successful solver response is missing result fields")
   ((and (equal (alist-get 'status response) "ok")
         (my/lifeos-solver--solve-result-validation-error
          (alist-get 'baseline response) "Baseline")))
    ((and (equal (alist-get 'status response) "ok")
          (alist-get 'scenario response)
         (my/lifeos-solver--solve-result-validation-error
           (alist-get 'scenario response) "Scenario")))
    ((and (equal (alist-get 'status response) "ok")
          (my/lifeos-solver--portfolio-validation-error
           (alist-get 'baselinePortfolio response) "Baseline portfolio")))
    ((and (equal (alist-get 'status response) "ok")
          (alist-get 'scenarioPortfolio response)
          (my/lifeos-solver--portfolio-validation-error
           (alist-get 'scenarioPortfolio response) "Scenario portfolio")))
    ((and (equal (alist-get 'status response) "ok")
          (not (eq (null (alist-get 'scenario response))
                   (null (alist-get 'scenarioPortfolio response)))))
     "Scenario solve and portfolio results must be paired")
    ((and (equal (alist-get 'status response) "ok")
          (alist-get 'comparison response)
          (my/lifeos-solver--comparison-validation-error
           (alist-get 'comparison response))))
    ((and (equal (alist-get 'status response) "ok")
          (not (eq (null (alist-get 'scenario response))
                   (null (alist-get 'comparison response)))))
     "Scenario solve and comparison must be paired")
   ((and (equal (alist-get 'status response) "ok")
         (not (listp (alist-get 'negotiationResults response))))
    "Successful solver response has malformed negotiation results")
   ((and (equal (alist-get 'status response) "ok")
         (not (seq-every-p #'my/lifeos-solver--negotiation-result-valid-p
                           (alist-get 'negotiationResults response))))
    "Successful solver response has a malformed negotiation result")))

(defun my/lifeos-solver--response-error-message (response exit-status stderr)
  "Describe structured RESPONSE, EXIT-STATUS, and isolated STDERR."
  (let* ((status (alist-get 'status response))
         (errors (alist-get 'errors response))
         (details
          (mapconcat
           (lambda (error)
             (let ((path (alist-get 'path error))
                   (message (alist-get 'message error)))
               (if (and (stringp path) (not (string-empty-p path)))
                   (format "%s: %s" path message)
                 (format "%s" message))))
           errors "; ")))
    (string-join
     (delq nil
           (list (format "Solver returned %s (exit %d)" status exit-status)
                 (unless (string-empty-p details) details)
                 (unless (string-empty-p stderr) (format "stderr: %s" stderr))))
     ": ")))

(defun my/lifeos-solver--request-stage-count (request)
  "Return worst-case Z3 checks performed for REQUEST."
  (let* ((stress-count (length (alist-get 'stressProfiles request)))
          (scenario (alist-get 'scenario request))
          (quantum (alist-get 'schedulingQuantumMinutes request))
          (stages (+ 4 stress-count
                     (if (or (null scenario) (eq scenario :null))
                         0
                       (+ 4 stress-count)))))
    (dolist (query (append (alist-get 'negotiationQueries request) nil) stages)
      (cl-incf stages
               (pcase (alist-get 'kind query)
                 ((or "maximum-deadline-only-discretionary-duration"
                      "maximum-safe-discretionary-duration")
                  (let* ((units (max 1 (floor (- (alist-get 'maximumEnd query)
                                                  (alist-get 'start query))
                                               quantum)))
                         (search-checks (1+ (ceiling (log units 2)))))
                    (1+ search-checks)))
                 ("latest-safe-discretionary-start"
                  (let* ((first (* quantum
                                   (ceiling (alist-get 'earliestStart query)
                                            quantum)))
                         (last (* quantum
                                  (floor (- (alist-get 'latestEnd query)
                                            (alist-get 'durationMinutes query))
                                         quantum))))
                    (max 1 (1+ (floor (- last first) quantum)))))
                  ("minimal-commitment-unlock-set"
                   (expt 2 (length (alist-get 'candidateCommitmentIds query))))
                  ("maximum-project-effort"
                   (+ 2 (ceiling (log (max 1 (/ (alist-get 'maximumEffortMinutes query)
                                                 quantum)) 2))))
                  ("latest-safe-project-start"
                   (max 1 (1+ (floor (- (alist-get 'latestStart query)
                                        (alist-get 'earliestStart query)) quantum))))
                  ("earliest-feasible-project-deadline"
                   (+ 2 (ceiling (log (max 1 (/ (- (alist-get 'latestDeadline query)
                                                    (alist-get 'earliestDeadline query))
                                                 quantum)) 2))))
                  ("minimal-project-defer-set"
                   (expt 2 (length (alist-get 'candidateProjectIds query))))
                  (_ 1))))))

(defun my/lifeos-solver--process-timeout-seconds (request)
  "Return a conservative end-to-end timeout for REQUEST."
  (+ 2.0 (* (my/lifeos-solver--request-stage-count request)
            (/ (alist-get 'timeoutMs request) 1000.0))))

(defun my/lifeos-solver--refresh-report-buffer ()
  "Rerender an existing solver report while preserving visible positions."
  (when-let* ((buffer (get-buffer "*LifeOS Solver*")))
    (let ((positions (mapcar (lambda (window)
                               (cons window (window-point window)))
                             (get-buffer-window-list buffer nil t))))
      (with-current-buffer buffer
        (let ((inhibit-read-only t)
              (position (point)))
          (erase-buffer)
          (my/lifeos-solver--render-report)
          (special-mode)
          (goto-char (min position (point-max)))))
      (dolist (entry positions)
        (when (window-live-p (car entry))
           (set-window-point (car entry)
                             (min (cdr entry)
                                  (with-current-buffer buffer (point-max)))))))))

(defun my/lifeos-solver--refresh-portfolio-buffer ()
  "Rerender Portfolio Review while preserving visible positions."
  (when-let* ((buffer (get-buffer "*LifeOS Portfolio Review*")))
    (let ((positions (mapcar (lambda (window)
                               (cons window (window-point window)))
                             (get-buffer-window-list buffer nil t))))
      (with-current-buffer buffer
        (let* ((inhibit-read-only t)
               (position (point))
               (pair (my/lifeos-solver--portfolio-display-pair)))
          (erase-buffer)
          (my/lifeos-portfolio-review-mode)
          (my/lifeos-solver--render-portfolio-review (car pair) (cdr pair))
          (goto-char (min position (point-max)))))
      (dolist (entry positions)
        (when (window-live-p (car entry))
          (set-window-point
           (car entry)
           (min (cdr entry) (with-current-buffer buffer (point-max)))))))))

(defun my/lifeos-solver--process-sentinel (process _event)
  "Publish a completed solver PROCESS unless its request is stale."
  (when (memq (process-status process) '(exit signal))
    (my/lifeos-solver--cancel-process-timer process)
    (let* ((request-id (process-get process 'lifeos-request-id))
           (stderr-buffer (process-get process 'lifeos-stderr-buffer))
            (stderr (if (buffer-live-p stderr-buffer)
                        (with-current-buffer stderr-buffer
                          (string-trim (buffer-string)))
                      ""))
            (accepted (equal request-id my/lifeos-solver-current-request-id)))
      (when accepted
        (setq my/lifeos-solver-last-request-context
              (process-get process 'lifeos-context))
        (unless (process-get process 'lifeos-timed-out)
          (with-current-buffer (process-buffer process)
            (let ((raw (string-trim (buffer-string))))
              (condition-case error-data
                  (let* ((response (json-parse-string
                                    raw :object-type 'alist :array-type 'list
                                    :null-object nil :false-object nil))
                         (validation-error
                          (my/lifeos-solver--response-validation-error
                           response request-id)))
                    (cond
                     (validation-error
                      (setq my/lifeos-solver-last-error
                            (string-join
                             (delq nil
                                   (list validation-error
                                         (unless (string-empty-p stderr)
                                           (format "stderr: %s" stderr))))
                             ": ")))
                     ((and (zerop (process-exit-status process))
                           (equal (alist-get 'status response) "ok"))
                      (let ((context (process-get process 'lifeos-context)))
                        (setq my/lifeos-solver-last-good-result response
                              my/lifeos-solver-last-good-json raw
                              my/lifeos-solver-last-error nil
                              my/lifeos-solver-source-markers
                              (plist-get context :source-markers)
                              my/lifeos-solver-last-good-request-context
                              context)))
                     (t
                      (setq my/lifeos-solver-last-error
                            (my/lifeos-solver--response-error-message
                             response (process-exit-status process) stderr)))))
                (error
                 (setq my/lifeos-solver-last-error
                       (string-join
                        (delq nil
                              (list (error-message-string error-data)
                                    (unless (string-empty-p stderr)
                                      (format "stderr: %s" stderr))))
                        ": ")))))))))
      (when (eq process my/lifeos-solver-process)
        (setq my/lifeos-solver-process nil))
      (when (equal (process-get process 'lifeos-request-id)
                   my/lifeos-solver-current-request-id)
        (my/lifeos-solver--refresh-report-buffer)
        (my/lifeos-solver--refresh-portfolio-buffer)))
    (when (buffer-live-p (process-buffer process))
      (kill-buffer (process-buffer process)))
    (when (buffer-live-p (process-get process 'lifeos-stderr-buffer))
      (kill-buffer (process-get process 'lifeos-stderr-buffer))))

(defun my/lifeos-solver--snapshot (&optional analysis forecast)
  "Capture ANALYSIS, FORECAST, normalized request, and source markers together."
  (let* ((analysis (or analysis
                       (plist-get my/lifeos-project-analysis-cache :analysis)
                       (my/lifeos-graph-analysis)))
         (forecast (or forecast
                       (and (eq analysis
                                (plist-get my/lifeos-project-analysis-cache :analysis))
                            (plist-get my/lifeos-project-analysis-cache :forecast))))
         (source-markers (make-hash-table :test #'equal))
         (captured-at (current-time))
         (request (my/lifeos-solver-normalize
                   analysis nil captured-at source-markers nil)))
    (list :request-id (alist-get 'requestId request)
          :request request :analysis analysis :forecast forecast
          :captured-at captured-at :source-markers source-markers)))

(defun my/lifeos-solver--start-request (context)
  "Start the solver for the prepared request in CONTEXT."
  (let* ((request (plist-get context :request))
         (request-id (alist-get 'requestId request))
         (buffer (generate-new-buffer (format " *LifeOS Solver %s*" request-id)))
         (stderr-buffer
          (generate-new-buffer (format " *LifeOS Solver stderr %s*" request-id)))
         (command (or my/lifeos-solver-command
                      (my/lifeos-solver--default-command))))
    (setq context (plist-put context :request-id request-id))
    (my/lifeos-solver--cancel-process)
    (setq my/lifeos-solver-current-request-id request-id
          my/lifeos-solver-last-error nil
          my/lifeos-solver-process
          (make-process :name (format "lifeos-solver-%s" request-id)
                        :buffer buffer :stderr stderr-buffer :command command
                        :connection-type 'pipe :noquery t :sentinel nil))
    (process-put my/lifeos-solver-process 'lifeos-request-id request-id)
    (process-put my/lifeos-solver-process 'lifeos-stderr-buffer stderr-buffer)
    (process-put my/lifeos-solver-process 'lifeos-context context)
    (setq my/lifeos-solver-process-timer
          (run-at-time (my/lifeos-solver--process-timeout-seconds request)
                       nil #'my/lifeos-solver--process-timeout
                       my/lifeos-solver-process request-id))
    (process-put my/lifeos-solver-process 'lifeos-timer
                 my/lifeos-solver-process-timer)
    (set-process-sentinel my/lifeos-solver-process
                          #'my/lifeos-solver--process-sentinel)
    (process-send-string my/lifeos-solver-process (json-serialize request))
    (process-send-eof my/lifeos-solver-process)
    (my/lifeos-solver--refresh-portfolio-buffer)
    request-id))

(defun my/lifeos-solver--supersede-request-before-normalization ()
  "Prevent an older request from publishing while new input is normalized."
  (setq my/lifeos-solver-current-request-id nil)
  (my/lifeos-solver--cancel-process)
  (setq my/lifeos-solver-process nil))

(defun my/lifeos-solver-request-shadow
    (&optional analysis scenario negotiation-queries forecast)
  "Asynchronously solve ANALYSIS with SCENARIO and NEGOTIATION-QUERIES.
Automatic shadow callers omit NEGOTIATION-QUERIES, keeping background work
query-free.  FORECAST can pair an already captured heuristic snapshot."
  (interactive)
  (when my/lifeos-solver-shadow-enabled
    (my/lifeos-solver--supersede-request-before-normalization)
    (let* ((context (my/lifeos-solver--snapshot analysis forecast))
           (request (copy-tree (plist-get context :request))))
      (setf (alist-get 'scenario request) (or scenario :null)
            (alist-get 'negotiationQueries request) (vconcat negotiation-queries))
      (setq context (plist-put context :request request))
      (my/lifeos-solver--start-request context))))

(defun my/lifeos-solver--format-minute (minute)
  "Format epoch MINUTE as a local date and time."
  (if (numberp minute)
      (format-time-string "%a %Y-%m-%d %H:%M %Z"
                          (seconds-to-time (* minute 60)))
    "unknown"))

(defun my/lifeos-solver--format-duration (minutes)
  "Format MINUTES for a solver report."
  (if (numberp minutes) (my/lifeos--format-minutes minutes) "unknown"))

(defun my/lifeos-solver--context-record (context id)
  "Find stable ID in CONTEXT's captured analysis."
  (let ((analysis (plist-get context :analysis)))
    (seq-find (lambda (record)
                (or (equal (plist-get record :id) id)
                    (equal (my/lifeos-solver--source-id
                            record
                            (cond ((plist-get record :definition-status) "project")
                                  ((plist-get record :project-key) "task")
                                  (t "source")))
                           id)))
               (append (plist-get analysis :all-records)
                       (plist-get analysis :projects)
                       (plist-get analysis :orphan-records)))))

(defun my/lifeos-solver--title (context id)
  "Return the captured title for stable ID in CONTEXT."
  (or (plist-get (my/lifeos-solver--context-record context id) :title) id "unknown"))

(defun my/lifeos-solver--insert-source (context id)
  "Insert ID with a source button when CONTEXT has a live marker."
  (let* ((markers (plist-get context :source-markers))
         (marker (and markers (gethash id markers))))
    (if (and marker (marker-buffer marker))
        (insert-text-button
         (my/lifeos-solver--title context id)
          'follow-link t 'help-echo (format "Visit Org source %s" id)
          'action (lambda (_) (my/lifeos-solver--visit-marker marker id)))
      (insert (my/lifeos-solver--title context id)))
    (unless (equal (my/lifeos-solver--title context id) id)
      (insert (format " [%s]" id)))))

(defun my/lifeos-solver--record-source-id (record kind)
  "Return RECORD's captured source ID using KIND as fallback namespace."
  (my/lifeos-solver--source-id record kind))

(defun my/lifeos-solver--insert-record-source (context record kind)
  "Insert a source link for RECORD of KIND using captured CONTEXT."
  (my/lifeos-solver--insert-source
   context (my/lifeos-solver--record-source-id record kind)))

(defun my/lifeos-solver--insert-list (heading values)
  "Insert HEADING and string VALUES."
  (insert (format "\n%s\n" heading))
  (if values
      (dolist (value (append values nil)) (insert (format "  - %s\n" value)))
    (insert "  None\n")))

(defun my/lifeos-solver--insert-placement-list (heading values context &optional id-key)
  "Insert placement VALUES under HEADING using CONTEXT and ID-KEY."
  (insert (format "\n%s\n" heading))
  (if (not values)
      (insert "  None\n")
    (dolist (placement (append values nil))
      (insert "  - ")
      (my/lifeos-solver--insert-source
       context (alist-get (or id-key 'taskId) placement))
      (when-let* ((project-id (alist-get 'projectId placement)))
        (insert " / project ")
        (my/lifeos-solver--insert-source context project-id))
      (insert (format ": %s to %s%s\n"
                      (my/lifeos-solver--format-minute (alist-get 'start placement))
                      (my/lifeos-solver--format-minute (alist-get 'end placement))
                       (if-let* ((kind (alist-get 'kind placement)))
                           (format " (%s)" kind) ""))))))

(defun my/lifeos-solver--format-extension-value (value)
  "Format optional protocol extension VALUE without assuming its shape."
  (condition-case nil
      (json-serialize value)
    (error (format "%S" value))))

(defun my/lifeos-solver--extension-fields (object regexp &optional excluded)
  "Return OBJECT fields whose names match REGEXP, except EXCLUDED symbols."
  (seq-filter (lambda (entry)
                (and (not (memq (car entry) excluded))
                     (string-match-p regexp (downcase (symbol-name (car entry))))))
              object))

(defun my/lifeos-solver--insert-solve-result (heading result context)
  "Insert one solver RESULT named HEADING using CONTEXT."
  (insert (format "\n%s\n%s\n" heading (make-string (length heading) ?=)))
  (if (not result)
      (insert "Not requested or unavailable.\n")
    (insert (format "Feasibility: %s\nSafety: %s\nResilience: %s\n"
                    (or (alist-get 'feasibility result) "unknown")
                    (or (alist-get 'safety result) "not established")
                    (or (alist-get 'resilience result) "not established")))
    (my/lifeos-solver--insert-list "Assumptions" (alist-get 'assumptions result))
    (my/lifeos-solver--insert-placement-list
     "Task placements" (alist-get 'placements result) context)
    (my/lifeos-solver--insert-placement-list
     "Sleep placements" (alist-get 'sleepPlacements result) context 'id)
    (my/lifeos-solver--insert-placement-list
     "Reserve placements" (alist-get 'reservePlacements result) context 'id)
    (when (assq 'deadlineMargins result)
      (insert "\nDeadline margins\n")
      (if-let* ((margins (alist-get 'deadlineMargins result)))
          (dolist (margin margins)
            (insert "  - ")
            (let ((source-id (or (alist-get 'sourceId margin)
                                 (alist-get 'taskId margin)
                                 (alist-get 'projectId margin)
                                 (alist-get 'id margin))))
              (if source-id
                  (my/lifeos-solver--insert-source context source-id)
                (insert "unknown source")))
            (insert (format ": %s\n"
                            (my/lifeos-solver--format-extension-value margin))))
        (insert "  None\n")))
    (let ((extensions
           (my/lifeos-solver--extension-fields
            result "\\(?:deadline.*margin\\|margin.*deadline\\|relax\\)"
            '(deadlineMargins conflicts))))
      (when extensions
        (insert "\nAdditional margin/relaxation data\n")
        (dolist (entry extensions)
          (insert (format "  - %s: %s\n" (car entry)
                          (my/lifeos-solver--format-extension-value
                           (cdr entry)))))))
    (insert "\nIntention outcomes\n")
    (if-let* ((intentions (alist-get 'intentions result)))
        (dolist (outcome intentions)
          (insert "  - ")
          (my/lifeos-solver--insert-source context (alist-get 'id outcome))
          (insert (format ": allocated %s; minimum shortfall %s; target deviation %s; maximum excess %s\n"
                          (my/lifeos-solver--format-duration
                           (alist-get 'allocatedMinutes outcome))
                          (my/lifeos-solver--format-duration
                           (alist-get 'minimumShortfallMinutes outcome))
                          (my/lifeos-solver--format-duration
                           (alist-get 'targetDeviationMinutes outcome))
                          (my/lifeos-solver--format-duration
                           (alist-get 'maximumExcessMinutes outcome)))))
      (insert "  None\n"))
    (insert "\nConflicts\n")
    (if-let* ((conflicts (alist-get 'conflicts result)))
        (dolist (conflict conflicts)
          (insert "  - ")
          (my/lifeos-solver--insert-source context (alist-get 'sourceId conflict))
           (insert (format ": %s [%s]" (alist-get 'message conflict)
                           (alist-get 'kind conflict)))
          (when (alist-get 'shared conflict)
            (insert "; shared/global constraint"))
          (when-let* ((ids (alist-get 'taskIds conflict)))
            (insert "; tasks ")
            (let ((first t))
              (dolist (id ids)
                (unless first (insert ", "))
                (setq first nil)
                (my/lifeos-solver--insert-source context id))))
          (when-let* ((ids (alist-get 'projectIds conflict)))
            (insert "; projects ")
            (let ((first t))
              (dolist (id ids)
                (unless first (insert ", "))
                (setq first nil)
                (my/lifeos-solver--insert-source context id))))
          (dolist (entry (my/lifeos-solver--extension-fields conflict "relax"))
            (insert (format "; %s %s" (car entry)
                            (my/lifeos-solver--format-extension-value
                             (cdr entry)))))
          (insert "\n"))
      (insert "  None\n"))
    (insert "\nStress results\n")
    (if-let* ((stress (alist-get 'stressResults result)))
        (dolist (item stress)
          (insert (format "  - %s: %s\n" (alist-get 'id item)
                          (alist-get 'feasibility item))))
      (insert "  None\n"))
    (my/lifeos-solver--insert-list
     "Unlocked commitments" (alist-get 'unlockedCommitmentIds result))))

(defun my/lifeos-solver-discrepancies (&optional result context)
  "Classify captured heuristic FORECAST against solver baseline by stable ID."
  (let* ((result (or result my/lifeos-solver-last-good-result))
         (context (or context my/lifeos-solver-last-good-request-context))
         (baseline (alist-get 'baseline result))
         (forecast (plist-get context :forecast))
         (heuristic (plist-get forecast :placements))
         (solver (and baseline (alist-get 'placements baseline)))
         (ids (sort (delete-dups
                     (append (mapcar (lambda (item) (plist-get item :id)) heuristic)
                             (mapcar (lambda (item) (alist-get 'taskId item)) solver)))
                    #'string<))
         output)
    (dolist (id ids (nreverse output))
      (let* ((heuristic-placement
              (seq-find (lambda (item) (equal (plist-get item :id) id)) heuristic))
             (solver-placement
              (seq-find (lambda (item) (equal (alist-get 'taskId item) id)) solver))
             (record (my/lifeos-solver--context-record context id))
             (request-task
              (seq-find (lambda (item) (equal (alist-get 'id item) id))
                        (append (alist-get 'tasks (plist-get context :request)) nil)))
             (failure
              (seq-find (lambda (item) (equal (plist-get item :id) id))
                        (plist-get forecast :failures)))
             (classification
              (cond
               ((or (not baseline)
                    (equal (alist-get 'feasibility baseline) "UNKNOWN"))
                'solver-unknown)
               ((and heuristic-placement solver-placement)
                (if (= (my/lifeos-solver--minute (plist-get heuristic-placement :start))
                       (alist-get 'start solver-placement))
                    'same-placement 'different-placement))
               (heuristic-placement 'heuristic-only)
               (solver-placement 'solver-only)
               (t 'solver-unknown)))
             (expected
              (cond
               ((and heuristic-placement (not request-task))
                (format "solver omitted %s task"
                        (or (plist-get record :state) "invalid")))
               ((and solver-placement failure)
                (format "heuristic rejected task: %s" (plist-get failure :reason)))
               ((and heuristic-placement solver-placement
                     (eq (plist-get heuristic-placement :kind) 'fixed))
                "both preserve a fixed commitment"))))
        (push (list :id id :classification classification
                    :heuristic heuristic-placement :solver solver-placement
                    :expected-difference expected)
              output)))))

(defun my/lifeos-solver--insert-discrepancies (result context)
  "Insert heuristic-versus-solver discrepancies for RESULT and CONTEXT."
  (insert "\nHeuristic vs solver\n===================\n")
  (let ((items (my/lifeos-solver-discrepancies result context)))
    (if (not items)
        (insert "No task placements to compare.\n")
      (dolist (item items)
        (insert "  - ")
        (my/lifeos-solver--insert-source context (plist-get item :id))
        (insert (format ": %s" (plist-get item :classification)))
        (when-let* ((expected (plist-get item :expected-difference)))
          (insert (format " (expected constraint difference: %s)" expected)))
        (when-let* ((placement (plist-get item :heuristic)))
          (insert (format "; heuristic %s"
                          (my/lifeos-solver--format-minute
                           (my/lifeos-solver--minute
                            (plist-get placement :start))))))
        (when-let* ((placement (plist-get item :solver)))
          (insert (format "; solver %s"
                          (my/lifeos-solver--format-minute
                           (alist-get 'start placement)))))
        (insert "\n")))))

(defun my/lifeos-solver--insert-comparison-deltas (comparison)
  "Insert optional delta-valued extension fields from COMPARISON."
  (let ((deltas (seq-remove
                 (lambda (entry)
                   (memq (car entry)
                         '(interpretation movedTaskIds addedTaskIds droppedTaskIds
                           safetyTransition resilienceTransition)))
                 comparison)))
    (when deltas
      (insert "Deltas:\n")
      (dolist (entry deltas)
        (insert (format "  - %s: %s\n" (car entry)
                        (my/lifeos-solver--format-extension-value
                         (cdr entry))))))))

(defun my/lifeos-solver--insert-comparison (comparison context)
  "Insert structured COMPARISON using CONTEXT."
  (insert "\nScenario comparison\n===================\n")
  (if (not comparison)
      (insert "No scenario comparison.\n")
    (insert (format "%s\nSafety: %s -> %s\nResilience: %s -> %s\n"
                    (alist-get 'interpretation comparison)
                    (or (alist-get 'baseline (alist-get 'safetyTransition comparison))
                        "unknown")
                    (or (alist-get 'scenario (alist-get 'safetyTransition comparison))
                        "unknown")
                    (or (alist-get 'baseline
                                   (alist-get 'resilienceTransition comparison))
                        "unknown")
                    (or (alist-get 'scenario
                                   (alist-get 'resilienceTransition comparison))
                        "unknown")))
    (dolist (spec '((movedTaskIds . "Moved")
                    (addedTaskIds . "Added")
                    (droppedTaskIds . "Dropped")))
      (insert (format "%s: " (cdr spec)))
      (if-let* ((ids (alist-get (car spec) comparison)))
          (let ((first t))
            (dolist (id ids)
              (unless first (insert ", "))
              (setq first nil)
              (my/lifeos-solver--insert-source context id)))
        (insert "none"))
      (insert "\n"))
    (my/lifeos-solver--insert-comparison-deltas comparison)))

(defun my/lifeos-solver--insert-negotiation-result (item)
  "Insert one discriminated negotiation result ITEM."
  (insert (format "\n%s [%s, %s]\n  Feasibility: %s\n"
                  (alist-get 'id item) (alist-get 'kind item)
                  (alist-get 'scope item) (alist-get 'feasibility item)))
  (pcase (alist-get 'kind item)
    ((or "maximum-deadline-only-discretionary-duration"
         "maximum-safe-discretionary-duration")
     (insert (format "  Maximum duration: %s\n  Tested: %s to %s\n"
                     (my/lifeos-solver--format-duration
                      (alist-get 'maximumDurationMinutes item))
                     (my/lifeos-solver--format-minute (alist-get 'testedStart item))
                     (my/lifeos-solver--format-minute
                      (alist-get 'testedMaximumEnd item)))))
    ("minimum-required-work-in-window"
     (insert (format "  Assurance: %s\n  Minimum required work: %s\n  Window: %s to %s\n"
                     (alist-get 'assurance item)
                     (my/lifeos-solver--format-duration
                      (alist-get 'minimumRequiredMinutes item))
                     (my/lifeos-solver--format-minute (alist-get 'testedStart item))
                     (my/lifeos-solver--format-minute (alist-get 'testedEnd item)))))
    ("latest-safe-discretionary-start"
     (insert (format "  Duration: %s\n  Latest safe start: %s\n  Tested: %s to %s\n"
                     (my/lifeos-solver--format-duration
                      (alist-get 'testedDurationMinutes item))
                     (my/lifeos-solver--format-minute (alist-get 'latestStart item))
                     (my/lifeos-solver--format-minute
                      (alist-get 'testedEarliestStart item))
                     (my/lifeos-solver--format-minute
                      (alist-get 'testedLatestEnd item)))))
    ("minimal-commitment-unlock-set"
     (insert (format "  Assurance: %s\n  Candidates: %s\n  Minimal unlock set: %s\n"
                     (alist-get 'assurance item)
                     (string-join (append (alist-get 'candidateCommitmentIds item) nil)
                                  ", ")
                      (if-let* ((ids (alist-get 'unlockedCommitmentIds item)))
                          (string-join (append ids nil) ", ") "unknown"))))
    ("maximum-project-effort"
     (insert (format "  Project: %s\n  Assurance: %s\n  Maximum effort: %s\n  Tested maximum: %s\n"
                     (alist-get 'projectId item) (alist-get 'assurance item)
                     (my/lifeos-solver--format-duration
                      (alist-get 'maximumEffortMinutes item))
                     (my/lifeos-solver--format-duration
                      (alist-get 'testedMaximumEffortMinutes item)))))
    ("minimum-project-work-in-window"
     (insert (format "  Project: %s\n  Assurance: %s\n  Minimum required work: %s\n  Window: %s to %s\n"
                     (alist-get 'projectId item) (alist-get 'assurance item)
                     (my/lifeos-solver--format-duration
                      (alist-get 'minimumRequiredMinutes item))
                     (my/lifeos-solver--format-minute (alist-get 'testedStart item))
                     (my/lifeos-solver--format-minute (alist-get 'testedEnd item)))))
    ("latest-safe-project-start"
     (insert (format "  Project: %s\n  Latest safe start: %s\n  Tested: %s to %s\n"
                     (alist-get 'projectId item)
                     (my/lifeos-solver--format-minute (alist-get 'latestStart item))
                     (my/lifeos-solver--format-minute
                      (alist-get 'testedEarliestStart item))
                     (my/lifeos-solver--format-minute
                      (alist-get 'testedLatestStart item)))))
    ("earliest-feasible-project-deadline"
     (insert (format "  Project: %s\n  Assurance: %s\n  Earliest deadline: %s\n  Tested: %s to %s\n"
                     (alist-get 'projectId item) (alist-get 'assurance item)
                     (my/lifeos-solver--format-minute
                      (alist-get 'earliestDeadline item))
                     (my/lifeos-solver--format-minute
                      (alist-get 'testedEarliestDeadline item))
                     (my/lifeos-solver--format-minute
                      (alist-get 'testedLatestDeadline item)))))
    ("minimal-project-defer-set"
     (insert (format "  Assurance: %s\n  Candidates: %s\n  Minimal defer set: %s\n  Conflict-involved: %s\n"
                     (alist-get 'assurance item)
                     (string-join (alist-get 'candidateProjectIds item) ", ")
                      (if-let* ((ids (alist-get 'deferredProjectIds item)))
                          (string-join ids ", ") "unknown")
                      (string-join (alist-get 'conflictProjectIds item) ", ")))))
  (dolist (assumption (append (alist-get 'assumptions item) nil))
    (insert (format "  Assumption: %s\n" assumption))))

(defun my/lifeos-solver--project-result (portfolio project-id)
  "Return PROJECT-ID's result from PORTFOLIO."
  (seq-find (lambda (item) (equal (alist-get 'projectId item) project-id))
            (alist-get 'projectResults portfolio)))

(defun my/lifeos-solver--project-next-finding (project result)
  "Return the next actionable finding for PROJECT and solver RESULT."
  (or (plist-get (car (plist-get project :diagnostics)) :message)
      (and result
           (equal (alist-get 'portfolioStatus result) "CONFLICT-INVOLVED")
           "Review portfolio conflict involvement")
      (and result
           (equal (alist-get 'isolatedFeasibility result) "UNKNOWN")
           "Resolve unknown isolated proof")
      "None"))

(defun my/lifeos-solver--insert-source-id-list (heading ids context)
  "Insert HEADING followed by source-linked IDS from CONTEXT."
  (insert (format "%s\n" heading))
  (if (not ids)
      (insert "  None\n")
    (dolist (id (append ids nil))
      (insert "  - ")
      (my/lifeos-solver--insert-source context id)
      (insert "\n"))))

(defun my/lifeos-solver--insert-project-drilldown
    (project result portfolio context)
  "Insert PROJECT drilldown using RESULT, PORTFOLIO, and CONTEXT."
  (let* ((section-start (point))
         (id (plist-get project :id))
         (key (plist-get project :key))
         (analysis (plist-get context :analysis))
         (request (plist-get context :request))
         (explicit
          (seq-filter (lambda (record)
                        (and (equal (plist-get record :project-key) key)
                             (plist-get record :executable)))
                      (plist-get analysis :all-records)))
         (virtual
          (seq-filter (lambda (task)
                        (and (equal (alist-get 'projectId task) id)
                             (equal (alist-get 'workType task) "virtual")))
                      (append (alist-get 'tasks request) nil))))
    (insert "\n")
    (my/lifeos-solver--insert-record-source context project "project")
    (insert "\n")
    (insert "Metadata errors\n")
    (if-let* ((diagnostics (plist-get project :diagnostics)))
        (progn
          (insert "  Run M-x my/lifeos-groom-project (M-; n p m) to fill project metadata.\n")
          (dolist (diagnostic diagnostics)
            (insert (format "  - %s: %s\n" (plist-get diagnostic :code)
                            (plist-get diagnostic :message)))))
      (insert "  None\n"))
    (insert "Explicit work\n")
    (if explicit
        (dolist (record explicit)
          (insert "  - ")
          (my/lifeos-solver--insert-record-source context record "task")
          (insert (format ": %s remaining\n"
                          (my/lifeos-solver--format-duration
                           (plist-get record :minutes)))))
      (insert "  None\n"))
    (insert "Virtual work\n")
    (if virtual
        (dolist (task virtual)
          (insert (format "  - %s: %s, %s, confidence %s\n"
                          (alist-get 'id task)
                          (my/lifeos-solver--format-duration
                           (alist-get 'durationMinutes task))
                          (alist-get 'workMode task)
                          (alist-get 'estimateConfidence
                                     (alist-get 'virtualWork task)))))
      (insert "  None\n"))
    (my/lifeos-solver--insert-source-id-list
     "Borrowed prerequisites"
     (and result (alist-get 'borrowedPrerequisiteTaskIds result)) context)
    (insert "Conflicts\n")
    (if (not result)
        (insert "  None\n")
      (dolist (task-id (alist-get 'conflictTaskIds result))
        (insert "  - task ")
        (my/lifeos-solver--insert-source context task-id)
        (insert "\n"))
      (dolist (project-id (alist-get 'conflictProjectIds result))
        (insert "  - project ")
        (my/lifeos-solver--insert-source context project-id)
        (insert "\n"))
      (unless (or (alist-get 'conflictTaskIds result)
                  (alist-get 'conflictProjectIds result))
        (insert "  None\n")))
    (my/lifeos-solver--insert-list
     "Assumptions"
     (and result (alist-get 'assumptions (alist-get 'isolatedResult result))))
    (when portfolio
      (insert (format "  Portfolio modeled subset: %s\n"
                      (if (alist-get 'modeledSubset portfolio) "yes" "no"))))
    (add-text-properties
     section-start (point)
     (list 'lifeos-project-marker (plist-get project :marker)
           'lifeos-project-id id))))

(defun my/lifeos-solver--insert-project-scenario-deltas (result)
  "Insert baseline-versus-scenario project deltas from RESULT."
  (insert "\nScenario project deltas\n=======================\n")
  (let* ((comparison (alist-get 'comparison result))
         (scenario-portfolio (alist-get 'scenarioPortfolio result))
         (baseline-portfolio (alist-get 'baselinePortfolio result))
         (deltas (alist-get 'projectDeltas comparison)))
    (if (not deltas)
        (insert "None.\n")
      (dolist (delta deltas)
        (let* ((id (alist-get 'projectId delta))
               (baseline (my/lifeos-solver--project-result baseline-portfolio id))
               (scenario (my/lifeos-solver--project-result scenario-portfolio id)))
          (insert (format "  - %s: definition %s -> %s; effort %s -> %s; isolated %s -> %s; portfolio %s -> %s; hard margin %s -> %s; safety margin %s -> %s; conflict projects %d -> %d\n"
                          id
                          (alist-get 'baselineDefinitionStatus delta)
                          (alist-get 'scenarioDefinitionStatus delta)
                          (my/lifeos-solver--format-duration
                           (alist-get 'baselineEffortMinutes delta))
                          (my/lifeos-solver--format-duration
                           (alist-get 'scenarioEffortMinutes delta))
                          (alist-get 'baselineIsolatedFeasibility delta)
                          (alist-get 'scenarioIsolatedFeasibility delta)
                          (alist-get 'baselinePortfolioStatus delta)
                          (alist-get 'scenarioPortfolioStatus delta)
                          (my/lifeos-solver--format-duration
                           (alist-get 'hardDeadlineMarginMinutes baseline))
                          (my/lifeos-solver--format-duration
                           (alist-get 'hardDeadlineMarginMinutes scenario))
                          (my/lifeos-solver--format-duration
                           (alist-get 'safetyMarginMinutes baseline))
                          (my/lifeos-solver--format-duration
                           (alist-get 'safetyMarginMinutes scenario))
                          (length (alist-get 'conflictProjectIds baseline))
                           (length (alist-get 'conflictProjectIds scenario)))))))))

(defun my/lifeos-solver--portfolio-display-pair ()
  "Return the solver RESULT and CONTEXT that Portfolio Review should display."
  (let ((running-context
         (and (processp my/lifeos-solver-process)
              (process-live-p my/lifeos-solver-process)
              (process-get my/lifeos-solver-process 'lifeos-context))))
    (cons my/lifeos-solver-last-good-result
          (or running-context
              my/lifeos-solver-last-good-request-context
              (condition-case nil
                  (my/lifeos-solver--snapshot)
                (error nil))))))

(defun my/lifeos-solver--portfolio-evidence-state (result context)
  "Return Portfolio Review evidence state for RESULT and CONTEXT."
  (let* ((running (and (processp my/lifeos-solver-process)
                       (process-live-p my/lifeos-solver-process)))
         (request-id (and context
                          (alist-get 'requestId (plist-get context :request))))
         (result-id (and result (alist-get 'requestId result))))
    (cond
     (running "RUNNING")
     ((not (plist-get context :analysis)) "UNAVAILABLE")
     ((not result) "LOCAL ONLY")
     ((or my/lifeos-project-analysis-stale
          (not (equal request-id result-id))) "STALE")
     (t "CURRENT"))))

(defun my/lifeos-solver--render-portfolio-review (&optional result context)
  "Render a read-only portfolio review for paired RESULT and CONTEXT."
  (let* ((context (or context my/lifeos-solver-last-good-request-context))
         (analysis (plist-get context :analysis))
         (portfolio (and result (alist-get 'baselinePortfolio result)))
         (projects (plist-get analysis :projects))
         (evidence-state
          (my/lifeos-solver--portfolio-evidence-state result context))
         (inventory-incomplete
          (seq-some (lambda (project)
                      (and (eq (plist-get project :commitment) 'committed)
                           (eq (plist-get project :definition-status) 'incomplete)))
                    projects)))
    (setq-local my/lifeos-portfolio-review-context context
                my/lifeos-portfolio-review-result result)
    (insert "Portfolio Review\n================\n")
    (insert "Compare project definitions, local effort, and solver evidence.\n")
    (insert "READ-ONLY: reviewing and refreshing never writes Org or calendar data.\n")
    (insert (format "Evidence: %s%s\n"
                    evidence-state
                    (if (and result (member evidence-state '("RUNNING" "STALE")))
                        " (older accepted evidence is shown below)" "")))
    (when (equal evidence-state "UNAVAILABLE")
      (insert (format "Analysis error: %s\n"
                      (or my/lifeos-solver-last-error
                          "No usable project analysis is available"))))
    (insert (format "Planning status: %s\n"
                    (my/lifeos-schedule-portfolio-status result context)))
    (insert "Rows summarize projects; drilldowns explain metadata, work, assumptions, and conflicts.\n")
    (insert "Controls: r refresh, s schedule candidate, n/p next/previous project, RET source, g groom, h help, q quit.\n")
    (when portfolio
      (insert (format "Portfolio definition: %s; modeled feasibility: %s; safety: %s%s\n"
                      (if inventory-incomplete "INCOMPLETE"
                        (alist-get 'definitionStatus portfolio))
                      (alist-get 'feasibility portfolio)
                      (or (alist-get 'safety portfolio) "unknown")
                      (if (alist-get 'modeledSubset portfolio) "; modeled subset" ""))))
    (insert "\nProject | Commitment | Definition | Deadline | Total | Explicit | Virtual | Isolated | Portfolio | Hard margin | Safety margin | Confidence | Next finding\n")
    (insert (make-string 180 ?-) "\n")
    (dolist (project projects)
      (let* ((row-start (point))
             (id (plist-get project :id))
             (project-result (and id (my/lifeos-solver--project-result portfolio id))))
        (my/lifeos-solver--insert-record-source context project "project")
        (insert (format " | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s\n"
                        (upcase (symbol-name (plist-get project :commitment)))
                        (upcase (symbol-name (plist-get project :definition-status)))
                        (or (plist-get project :deadline) "missing")
                        (my/lifeos-solver--format-duration
                         (plist-get project :project-effort-minutes))
                        (my/lifeos-solver--format-duration
                         (plist-get project :explicit-remaining-minutes))
                        (my/lifeos-solver--format-duration
                         (plist-get project :unallocated-effort-minutes))
                        (or (alist-get 'isolatedFeasibility project-result) "UNKNOWN")
                        (or (alist-get 'portfolioStatus project-result)
                            (if (eq (plist-get project :commitment) 'uncommitted)
                                "UNCOMMITTED" "UNKNOWN"))
                        (my/lifeos-solver--format-duration
                         (alist-get 'hardDeadlineMarginMinutes project-result))
                        (my/lifeos-solver--format-duration
                         (alist-get 'safetyMarginMinutes project-result))
                        (or (plist-get project :estimate-confidence) "n/a")
                        (my/lifeos-solver--project-next-finding
                         project project-result)))
        (add-text-properties
         row-start (point)
         (list 'lifeos-project-marker (plist-get project :marker)
               'lifeos-project-id id))))
    (insert "\nProject drilldowns\n==================\n")
    (dolist (project projects)
      (my/lifeos-solver--insert-project-drilldown
       project (and (plist-get project :id)
                    (my/lifeos-solver--project-result
                     portfolio (plist-get project :id)))
       portfolio context))
    (insert "\nOrphan work\n===========\n")
    (if-let* ((records (plist-get analysis :orphan-records)))
        (dolist (record records)
          (insert "  - ")
          (my/lifeos-solver--insert-record-source context record "source")
          (insert "\n"))
      (insert "  None\n"))
    (when result
      (my/lifeos-solver--insert-project-scenario-deltas result))
    (insert "\nNegotiation answers\n===================\n")
    (if-let* ((items (and result (alist-get 'negotiationResults result))))
        (dolist (item items) (my/lifeos-solver--insert-negotiation-result item))
      (insert "None.\n"))))

(defun my/lifeos-portfolio-review--project-marker ()
  "Return the snapshot-bound project marker at point."
  (get-text-property (point) 'lifeos-project-marker))

(defun my/lifeos-portfolio-review--project-positions ()
  "Return source-ordered positions carrying distinct project markers."
  (let ((position (point-min)) seen positions)
    (while (< position (point-max))
      (let ((marker (get-text-property position 'lifeos-project-marker)))
        (when (and marker (not (memq marker seen)))
          (push marker seen)
          (push position positions))
        (setq position (next-single-property-change
                        position 'lifeos-project-marker nil (point-max)))))
    (nreverse positions)))

(defun my/lifeos-portfolio-review--move-project (forward-p)
  "Move to another project, forward when FORWARD-P, with wrapping."
  (let ((positions (my/lifeos-portfolio-review--project-positions)))
    (unless positions (user-error "Portfolio Review contains no projects"))
    (goto-char
     (or (seq-find (if forward-p
                       (lambda (position) (> position (point)))
                     (lambda (position) (< position (point))))
                   (if forward-p positions (reverse positions)))
         (if forward-p (car positions) (car (last positions)))))))

(defun my/lifeos-portfolio-review-next-project ()
  "Move to the next project in Portfolio Review."
  (interactive)
  (my/lifeos-portfolio-review--move-project t))

(defun my/lifeos-portfolio-review-previous-project ()
  "Move to the previous project in Portfolio Review."
  (interactive)
  (my/lifeos-portfolio-review--move-project nil))

(defun my/lifeos-portfolio-review-visit-source ()
  "Visit the snapshot-bound project source at point."
  (interactive)
  (let ((marker (my/lifeos-portfolio-review--project-marker)))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "Select a project row or drilldown with a live source"))
    (my/lifeos-solver--visit-marker marker
                                     (get-text-property (point) 'lifeos-project-id))))

(defun my/lifeos-portfolio-review-groom-project ()
  "Visit and groom the snapshot-bound project at point."
  (interactive)
  (my/lifeos-portfolio-review-visit-source)
  (call-interactively #'my/lifeos-groom-project))

(defun my/lifeos-portfolio-review-refresh ()
  "Rebuild local analysis and request fresh solver evidence when enabled."
  (interactive)
  (my/lifeos-refresh-project-analysis)
  (my/lifeos-solver--refresh-portfolio-buffer))

(defun my/lifeos-portfolio-review-help ()
  "Explain Portfolio Review actions in user-facing terms."
  (interactive)
  (with-help-window "*LifeOS Portfolio Help*"
    (princ "Portfolio Review compares project definitions, effort, and read-only solver evidence.\n\n")
    (princ "r refreshes local analysis and, when enabled, solver evidence.\n")
    (princ "s opens one transient schedule candidate from this exact current snapshot. Candidate edits remain read-only; only separately confirmed whole-plan acceptance writes the machine-owned Accepted schedule.\n")
    (princ "n/p move between projects. RET visits the captured source.\n")
    (princ "g visits the source and starts project grooming. q closes the review.\n")
    (princ "RUNNING and STALE may show older accepted evidence; LOCAL ONLY has no solver proof.\n")))

(defvar my/lifeos-portfolio-review-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "r") #'my/lifeos-portfolio-review-refresh)
    (define-key map (kbd "s") #'my/lifeos-portfolio-review-open-schedule)
    (define-key map (kbd "n") #'my/lifeos-portfolio-review-next-project)
    (define-key map (kbd "p") #'my/lifeos-portfolio-review-previous-project)
    (define-key map (kbd "RET") #'my/lifeos-portfolio-review-visit-source)
    (define-key map (kbd "g") #'my/lifeos-portfolio-review-groom-project)
    (define-key map (kbd "h") #'my/lifeos-portfolio-review-help)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for Portfolio Review.")

(define-derived-mode my/lifeos-portfolio-review-mode special-mode
  "LifeOS-Portfolio" "Read-only LifeOS Portfolio Review.")

(defun my/lifeos-solver-show-portfolio-review ()
  "Show the read-only Portfolio Review."
  (interactive)
  (let* ((pair (my/lifeos-solver--portfolio-display-pair))
         (result (car pair))
         (context (cdr pair))
         (buffer (get-buffer-create "*LifeOS Portfolio Review*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/lifeos-portfolio-review-mode)
        (my/lifeos-solver--render-portfolio-review result context)
        (goto-char (point-min))))
    (pop-to-buffer buffer)))

(defun my/lifeos-solver--render-report ()
  "Render the current LifeOS solver state into the current buffer."
  (let* ((result my/lifeos-solver-last-good-result)
         (context my/lifeos-solver-last-good-request-context)
         (running (and (processp my/lifeos-solver-process)
                       (process-live-p my/lifeos-solver-process)))
         (state-context (or (and running
                                 (process-get my/lifeos-solver-process
                                              'lifeos-context))
                            my/lifeos-solver-last-request-context context))
         (request (plist-get state-context :request))
         (stale (and result
                     (not (equal (alist-get 'requestId result)
                                 my/lifeos-solver-current-request-id))))
         (kind (cond
                ((and request (not (memq (alist-get 'scenario request) '(nil :null))))
                 "PROPOSED SCENARIO")
                ((and request (> (length (alist-get 'negotiationQueries request)) 0))
                 "READ-ONLY NEGOTIATION")
                (t "SHADOW"))))
    (insert "LifeOS Solver Report\n====================\n")
    (insert (format "Mode: READ-ONLY / %s (no Org writes)\n" kind))
    (insert (format "State: %s%s%s\n"
                    (if running "RUNNING" (if result "RESULT AVAILABLE" "NO RESULT"))
                    (if stale "; STALE result shown" "")
                    (if my/lifeos-solver-last-error "; ERROR context below" "")))
    (when my/lifeos-solver-current-request-id
      (insert (format "Current request: %s\n" my/lifeos-solver-current-request-id)))
    (when-let* ((attempt-id (plist-get my/lifeos-solver-last-request-context
                                       :request-id)))
      (insert (format "Last completed attempt: %s\n" attempt-id)))
    (when result
      (insert (format "Protocol: %s\nSolver: %s\nRequest: %s\nStatus: %s\n"
                      (alist-get 'protocolVersion result)
                      (alist-get 'solverVersion result)
                      (alist-get 'requestId result) (alist-get 'status result))))
    (when-let* ((captured (plist-get state-context :captured-at)))
      (insert (format "Captured: %s\n" (format-time-string "%c %Z" captured))))
    (when my/lifeos-solver-last-error
      (insert (format "Error: %s\n" my/lifeos-solver-last-error)))
    (if (not result)
        (insert "\nNo successful response has been accepted yet.\n")
      (my/lifeos-solver--insert-solve-result
       "Baseline" (alist-get 'baseline result) context)
      (my/lifeos-solver--insert-solve-result
       "Proposed scenario" (alist-get 'scenario result) context)
      (my/lifeos-solver--insert-comparison (alist-get 'comparison result) context)
      (insert "\nNegotiation results\n===================\n")
      (if-let* ((items (alist-get 'negotiationResults result)))
          (dolist (item items) (my/lifeos-solver--insert-negotiation-result item))
        (insert "None.\n"))
      (my/lifeos-solver--insert-discrepancies result context))))

(defun my/lifeos-solver-show-shadow-result ()
  "Show the dedicated read-only solver report."
  (interactive)
  (let ((buffer (get-buffer-create "*LifeOS Solver*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/lifeos-solver--render-report)
        (goto-char (point-min))
        (special-mode)))
    (pop-to-buffer buffer)))

(defalias 'my/lifeos-solver-show-report #'my/lifeos-solver-show-shadow-result)

(defun my/lifeos-solver-show-raw-json ()
  "Show the last accepted raw solver response separately."
  (interactive)
  (unless my/lifeos-solver-last-good-json
    (user-error "No successful LifeOS solver JSON is available"))
  (let ((buffer (get-buffer-create "*LifeOS Solver JSON*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert my/lifeos-solver-last-good-json)
        (json-pretty-print-buffer)
        (goto-char (point-min))
        (special-mode)))
    (pop-to-buffer buffer)))

(defun my/lifeos-solver-show-discrepancies ()
  "Show the report positioned at its heuristic-versus-solver section."
  (interactive)
  (my/lifeos-solver-show-shadow-result)
  (goto-char (point-min))
  (when (search-forward "Heuristic vs solver" nil t)
    (beginning-of-line)))

(defun my/lifeos-solver--read-minute (prompt default-minute)
  "Read a local date/time with PROMPT, defaulting to DEFAULT-MINUTE."
  (my/lifeos-solver--minute
   (org-read-date t t nil
                  (format "%s (local): " prompt)
                  (and default-minute
                       (seconds-to-time (* default-minute 60))))))

(defun my/lifeos-solver--choices (context collection &optional predicate)
  "Return display-to-ID choices from CONTEXT REQUEST COLLECTION.
PREDICATE, when non-nil, receives each protocol item."
  (let (choices)
    (dolist (item (append (alist-get collection (plist-get context :request)) nil)
                  (nreverse choices))
      (when (or (null predicate) (funcall predicate item))
        (let ((id (alist-get 'id item)))
          (push (cons (format "%s [%s]" (my/lifeos-solver--title context id) id)
                      id)
                choices))))))

(defun my/lifeos-solver--read-id (prompt choices)
  "Read an ID using PROMPT and display-to-ID CHOICES."
  (unless choices (user-error "No eligible LifeOS items are available"))
  (cdr (assoc (completing-read prompt choices nil t) choices)))

(defun my/lifeos-solver--read-duration (prompt &optional allow-empty)
  "Read an H:MM duration with PROMPT, optionally ALLOW-EMPTY."
  (let ((text (string-trim (read-string prompt))))
    (if (and allow-empty (string-empty-p text)) nil
      (let ((minutes (my/lifeos--duration-minutes text)))
        (unless (and (> minutes 0) (= (% minutes 15) 0))
          (user-error "Duration must be positive and aligned to 15 minutes"))
        minutes))))

(defun my/lifeos-solver--submit-scenario (context scenario)
  "Submit ephemeral SCENARIO using captured CONTEXT."
  (let ((request (copy-tree (plist-get context :request))))
    (setf (alist-get 'scenario request) scenario
          (alist-get 'negotiationQueries request) [])
    (my/lifeos-solver--start-request (plist-put context :request request))))

(defun my/lifeos-solver--stage-scenario (scenario)
  "Store SCENARIO as the current ephemeral scenario."
  (setq my/lifeos-solver-current-scenario scenario)
  (message "LifeOS scenario now has %d delta(s)"
           (+ (length (alist-get 'reservations scenario))
               (length (alist-get 'unlockedCommitmentIds scenario))
               (length (alist-get 'estimateChanges scenario))
               (length (alist-get 'intentionChanges scenario))
               (length (alist-get 'projectChanges scenario)))))

(defun my/lifeos-solver-scenario-reserve-command ()
  "Test an added busy interval without writing Org."
  (interactive)
  (let* ((context (my/lifeos-solver--snapshot))
         (request (plist-get context :request))
         (horizon (alist-get 'horizon request))
         (start (my/lifeos-solver--read-minute
                 "Busy interval start" (alist-get 'start horizon)))
         (end (my/lifeos-solver--read-minute "Busy interval end" (+ start 60)))
         (id (string-trim (read-string "Reservation ID: " "interactive-busy"))))
    (when (string-empty-p id) (user-error "Reservation ID cannot be empty"))
    (my/lifeos-solver--stage-scenario
     (my/lifeos-solver-scenario-reserve
      request start end id my/lifeos-solver-current-scenario))))

(defun my/lifeos-solver-scenario-estimate-command ()
  "Test a task estimate change without writing Org."
  (interactive)
  (let* ((context (my/lifeos-solver--snapshot))
         (request (plist-get context :request))
         (id (my/lifeos-solver--read-id
              "Task estimate to change: "
              (my/lifeos-solver--choices context 'tasks)))
         (minutes (my/lifeos-solver--read-duration "New remaining estimate (H:MM): ")))
    (my/lifeos-solver--stage-scenario
     (my/lifeos-solver-scenario-estimate-change
      request id minutes my/lifeos-solver-current-scenario))))

(defun my/lifeos-solver-scenario-intention-command ()
  "Test intention bounds without writing Org."
  (interactive)
  (let* ((context (my/lifeos-solver--snapshot))
         (request (plist-get context :request))
         (id (my/lifeos-solver--read-id
              "Intention to change: "
              (my/lifeos-solver--choices context 'intentions)))
         (minimum (my/lifeos-solver--read-duration
                   "Minimum (H:MM, blank for none): " t))
         (target (my/lifeos-solver--read-duration
                  "Target (H:MM, blank for none): " t))
         (maximum (my/lifeos-solver--read-duration
                   "Maximum (H:MM, blank for none): " t)))
    (my/lifeos-solver--stage-scenario
     (my/lifeos-solver-scenario-intention-bounds
      request id minimum target maximum my/lifeos-solver-current-scenario))))

(defun my/lifeos-solver-scenario-unlock-command ()
  "Test unlocking a fixed commitment without writing Org."
  (interactive)
  (let* ((context (my/lifeos-solver--snapshot))
         (request (plist-get context :request))
         (id (my/lifeos-solver--read-id
              "Fixed commitment to unlock: "
              (my/lifeos-solver--choices
               context 'tasks (lambda (item) (numberp (alist-get 'fixedStart item)))))))
    (my/lifeos-solver--stage-scenario
     (my/lifeos-solver-scenario-unlock
      request id my/lifeos-solver-current-scenario))))

(defun my/lifeos-solver-scenario-project-command ()
  "Change one project assumption in memory without writing Org."
  (interactive)
  (let* ((context (my/lifeos-solver--snapshot))
         (request (plist-get context :request))
         (project-id (my/lifeos-solver--read-id
                      "Project assumption to change: "
                      (my/lifeos-solver--choices context 'projects)))
         (project (seq-find (lambda (item)
                              (equal (alist-get 'id item) project-id))
                            (append (alist-get 'projects request) nil)))
         (field (completing-read
                 "Project assumption: "
                 '("total effort" "deadline" "commitment" "work mode"
                   "planning chunk" "estimate confidence") nil t))
         change)
    (pcase field
      ("total effort"
       (setq change `((projectEffortMinutes
                       . ,(my/lifeos-solver--read-duration
                           "New total project effort (H:MM): ")))))
      ("deadline"
       (setq change `((deadline . ,(my/lifeos-solver--read-minute
                                    "New project deadline"
                                    (alist-get 'deadline project))))))
      ("commitment"
       (setq change `((commitment . ,(completing-read
                                      "Commitment: "
                                      '("COMMITTED" "UNCOMMITTED") nil t)))))
      ("work mode"
       (setq change `((defaultWorkMode . ,(completing-read
                                           "Default work mode: "
                                           my/lifeos-work-mode-values nil t)))))
      ("planning chunk"
       (setq change `((planningChunkMinutes
                       . ,(my/lifeos-solver--read-duration
                           "New planning chunk (H:MM): ")))))
      ("estimate confidence"
       (setq change `((estimateConfidence . ,(completing-read
                                              "Estimate confidence: "
                                               my/lifeos-estimate-confidence-values nil t))))))
    (my/lifeos-solver--stage-scenario
     (my/lifeos-solver-scenario-project-change
      request project-id change my/lifeos-solver-current-scenario))))

(defun my/lifeos-solver-scenario-defer-project-command ()
  "Mark one project uncommitted in the in-memory scenario only."
  (interactive)
  (let* ((context (my/lifeos-solver--snapshot))
         (request (plist-get context :request))
         (project-id (my/lifeos-solver--read-id
                      "Project to defer: "
                      (my/lifeos-solver--choices context 'projects))))
    (my/lifeos-solver--stage-scenario
     (my/lifeos-solver-scenario-project-change
      request project-id '((commitment . "UNCOMMITTED"))
      my/lifeos-solver-current-scenario))))

(defun my/lifeos-solver-scenario-clear-command ()
  "Clear the current ephemeral scenario."
  (interactive)
  (setq my/lifeos-solver-current-scenario nil)
  (message "LifeOS scenario cleared"))

(defun my/lifeos-solver-scenario-run-command ()
  "Run the current ephemeral scenario without writing Org."
  (interactive)
  (unless my/lifeos-solver-current-scenario
    (user-error "No scenario deltas have been added"))
  (my/lifeos-solver--submit-scenario
   (my/lifeos-solver--snapshot) my/lifeos-solver-current-scenario))

(defun my/lifeos-solver-scenario-menu ()
  "Dispatch a read-only scenario experiment."
  (interactive)
  (pcase (completing-read
           "Scenario experiment: "
           '("add busy interval" "change estimate" "change intention bounds"
              "unlock commitment" "change project assumption" "defer project"
              "clear scenario" "run scenario") nil t)
    ("add busy interval" (call-interactively #'my/lifeos-solver-scenario-reserve-command))
    ("change estimate" (call-interactively #'my/lifeos-solver-scenario-estimate-command))
    ("change intention bounds"
     (call-interactively #'my/lifeos-solver-scenario-intention-command))
    ("unlock commitment" (call-interactively #'my/lifeos-solver-scenario-unlock-command))
    ("change project assumption"
     (call-interactively #'my/lifeos-solver-scenario-project-command))
    ("defer project"
     (call-interactively #'my/lifeos-solver-scenario-defer-project-command))
    ("clear scenario" (my/lifeos-solver-scenario-clear-command))
    ("run scenario" (my/lifeos-solver-scenario-run-command))))

(defun my/lifeos-solver--read-assurance ()
  "Read a negotiation assurance level."
  (completing-read "Assurance: " '("deadline-only" "safe") nil t nil nil "safe"))

(defun my/lifeos-solver-negotiate (kind)
  "Run an interactive read-only negotiation query of KIND."
  (interactive
   (list (completing-read
          "Negotiation: "
           '("maximum-deadline-only-discretionary-duration"
             "maximum-safe-discretionary-duration"
             "minimum-required-work-in-window"
             "latest-safe-discretionary-start"
             "minimal-commitment-unlock-set"
             "maximum-project-effort"
             "minimum-project-work-in-window"
             "latest-safe-project-start"
             "earliest-feasible-project-deadline"
             "minimal-project-defer-set") nil t)))
  (let* ((context (my/lifeos-solver--snapshot))
         (request (plist-get context :request))
         (scope (completing-read
                 "Negotiation scope: "
                 (if my/lifeos-solver-current-scenario
                     '("baseline" "scenario") '("baseline"))
                 nil t nil nil "baseline"))
         (horizon (alist-get 'horizon request))
         (id (format "interactive-%s" kind))
         query)
    (when (equal scope "scenario")
      (setf (alist-get 'scenario request)
            (copy-tree my/lifeos-solver-current-scenario)))
    (pcase kind
      ((or "maximum-deadline-only-discretionary-duration"
           "maximum-safe-discretionary-duration")
       (let* ((start (my/lifeos-solver--read-minute
                      "Discretionary start" (alist-get 'start horizon)))
              (end (my/lifeos-solver--read-minute "Maximum end" (+ start 120))))
         (setq query (my/lifeos-solver-negotiation-query
                       request kind id scope :start start :maximum-end end))))
      ("minimum-required-work-in-window"
       (let* ((start (my/lifeos-solver--read-minute
                      "Window start" (alist-get 'start horizon)))
              (end (my/lifeos-solver--read-minute "Window end" (+ start 480))))
         (setq query (my/lifeos-solver-negotiation-query
                       request kind id scope :start start :end end
                      :assurance (my/lifeos-solver--read-assurance)))))
      ("latest-safe-discretionary-start"
       (let* ((duration (my/lifeos-solver--read-duration
                         "Discretionary duration (H:MM): "))
              (start (my/lifeos-solver--read-minute
                      "Earliest start" (alist-get 'start horizon)))
              (end (my/lifeos-solver--read-minute "Latest end" (+ start 480))))
         (setq query (my/lifeos-solver-negotiation-query
                       request kind id scope :duration-minutes duration
                      :earliest-start start :latest-end end))))
      ("minimal-commitment-unlock-set"
       (let* ((choices (my/lifeos-solver--choices
                        context 'tasks
                        (lambda (item) (numberp (alist-get 'fixedStart item)))))
              (_ (unless choices (user-error "No fixed commitments are available")))
              (selected (completing-read-multiple
                         "Candidate commitments: " choices nil t))
              (ids (mapcar (lambda (display) (cdr (assoc display choices))) selected)))
          (setq query (my/lifeos-solver-negotiation-query
                        request kind id scope :candidate-commitment-ids ids
                        :assurance (my/lifeos-solver--read-assurance)))))
      ("maximum-project-effort"
       (let ((project-id (my/lifeos-solver--read-id
                          "Project: " (my/lifeos-solver--choices context 'projects))))
         (setq query (my/lifeos-solver-negotiation-query
                      request kind id scope :project-id project-id
                      :maximum-effort-minutes
                      (my/lifeos-solver--read-duration "Maximum effort to test (H:MM): ")
                      :assurance (my/lifeos-solver--read-assurance)))))
      ("minimum-project-work-in-window"
       (let* ((project-id (my/lifeos-solver--read-id
                           "Project: " (my/lifeos-solver--choices context 'projects)))
              (start (my/lifeos-solver--read-minute
                      "Window start" (alist-get 'start horizon)))
              (end (my/lifeos-solver--read-minute "Window end" (+ start 480))))
         (setq query (my/lifeos-solver-negotiation-query
                      request kind id scope :project-id project-id
                      :start start :end end
                      :assurance (my/lifeos-solver--read-assurance)))))
      ("latest-safe-project-start"
       (let* ((project-id (my/lifeos-solver--read-id
                           "Project: " (my/lifeos-solver--choices context 'projects)))
              (start (my/lifeos-solver--read-minute
                      "Earliest project start" (alist-get 'start horizon)))
              (latest (my/lifeos-solver--read-minute
                       "Latest project start" (+ start 480))))
         (setq query (my/lifeos-solver-negotiation-query
                      request kind id scope :project-id project-id
                      :earliest-start start :latest-start latest))))
      ("earliest-feasible-project-deadline"
       (let* ((project-id (my/lifeos-solver--read-id
                           "Project: " (my/lifeos-solver--choices context 'projects)))
              (earliest (my/lifeos-solver--read-minute
                         "Earliest deadline" (+ (alist-get 'start horizon) 15)))
              (latest (my/lifeos-solver--read-minute
                       "Latest deadline" (alist-get 'end horizon))))
         (setq query (my/lifeos-solver-negotiation-query
                      request kind id scope :project-id project-id
                      :earliest-deadline earliest :latest-deadline latest
                      :assurance (my/lifeos-solver--read-assurance)))))
      ("minimal-project-defer-set"
       (let* ((choices (my/lifeos-solver--choices context 'projects))
              (selected (completing-read-multiple
                         "Candidate projects: " choices nil t))
              (ids (mapcar (lambda (display) (cdr (assoc display choices))) selected)))
         (setq query (my/lifeos-solver-negotiation-query
                      request kind id scope :candidate-project-ids ids
                      :assurance (my/lifeos-solver--read-assurance))))))
    (setf (alist-get 'negotiationQueries request) (vector query))
    (my/lifeos-solver--start-request (plist-put context :request request))))

(defun my/lifeos-solver-negotiate-maximum-deadline-only ()
  "Query maximum deadline-only discretionary duration."
  (interactive)
  (my/lifeos-solver-negotiate "maximum-deadline-only-discretionary-duration"))

(defun my/lifeos-solver-negotiate-maximum-safe ()
  "Query maximum safe discretionary duration."
  (interactive)
  (my/lifeos-solver-negotiate "maximum-safe-discretionary-duration"))

(defun my/lifeos-solver-negotiate-minimum-required-work ()
  "Query minimum required work in a window."
  (interactive)
  (my/lifeos-solver-negotiate "minimum-required-work-in-window"))

(defun my/lifeos-solver-negotiate-latest-safe-start ()
  "Query latest safe discretionary start."
  (interactive)
  (my/lifeos-solver-negotiate "latest-safe-discretionary-start"))

(defun my/lifeos-solver-negotiate-minimal-unlock-set ()
  "Query a minimal commitment unlock set."
  (interactive)
  (my/lifeos-solver-negotiate "minimal-commitment-unlock-set"))

(defun my/lifeos-solver--visit-marker (marker source-id)
  "Visit captured Org MARKER for SOURCE-ID."
  (unless (and marker (marker-buffer marker))
    (user-error "No current Org source for %s" source-id))
  (pop-to-buffer (marker-buffer marker))
  (goto-char marker)
  (org-show-context))

(defun my/lifeos-solver-visit-source (source-id)
  "Visit normalized SOURCE-ID from the latest request."
  (interactive
   (list (completing-read "LifeOS source: "
                          (hash-table-keys my/lifeos-solver-source-markers)
                          nil t)))
  (my/lifeos-solver--visit-marker
   (gethash source-id my/lifeos-solver-source-markers) source-id))

(provide 'lifeos-solver)
;;; lifeos-solver.el ends here
