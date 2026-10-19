;; -*- lexical-binding: t -*-
;;; org/lifeos-schedule.el --- Adjustable LifeOS schedule candidates

(require 'cl-lib)
(require 'json)
(require 'org)
(require 'seq)
(require 'subr-x)
(require 'lifeos-planning)

(defcustom my/lifeos-schedule-debounce-delay 0.6
  "Idle seconds before checking an edited schedule candidate."
  :type 'number
  :group 'my/lifeos)

(defcustom my/lifeos-schedule-analysis-function
  #'my/lifeos-schedule--solver-analysis
  "Function called with a request plist and a response callback.
The function may call the callback synchronously or asynchronously."
  :type 'function
  :group 'my/lifeos)

(cl-defstruct (my/lifeos-schedule-candidate
               (:constructor my/lifeos-schedule--make-candidate))
  id revision condition input-fingerprint current-plan-fingerprint
  request-id horizon-start horizon-end boundary-adjustment context
  blocks fixed-blocks exclusions omissions estimate-overrides history
  evidence prior-evidence pending-request-id closed)

(defvar my/lifeos-schedule-active-candidate nil
  "The sole open schedule candidate, or nil.")
(defvar my/lifeos-schedule-debounce-timer nil)
(defvar my/lifeos-schedule-request-sequence 0)
(defvar my/lifeos-schedule-analysis-processes nil)
(defvar my/lifeos-schedule-restore-token nil
  "One-session token for restoring the most recently replaced plan.")
(defvar-local my/lifeos-schedule-buffer-candidate nil)

(defconst my/lifeos-schedule--plan-properties
  '("LIFEOS_PLAN_ID" "LIFEOS_PLAN_SOURCE_FINGERPRINT"
    "LIFEOS_PLAN_HORIZON_START" "LIFEOS_PLAN_HORIZON_END"
    "LIFEOS_PLAN_ACCEPTED_AT"))

(defun my/lifeos-schedule--planning-file ()
  (expand-file-name "planning.org" org-directory))

(defun my/lifeos-schedule--hash (text)
  (secure-hash 'sha256 (encode-coding-string (or text "") 'utf-8)))

(defun my/lifeos-schedule--iso-time (minute)
  (let ((raw (format-time-string "%Y-%m-%dT%H:%M:%S%z"
                                 (seconds-to-time (* minute 60)))))
    (concat (substring raw 0 -2) ":" (substring raw -2))))

(defun my/lifeos-schedule--format-minute (minute)
  (if (numberp minute)
      (format-time-string "%a %Y-%m-%d %H:%M %Z"
                          (seconds-to-time (* minute 60)))
    "unknown"))

(defun my/lifeos-schedule--parse-iso-minute (value label)
  (unless (and (stringp value)
               (string-match-p
                "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}[+-][0-9]\\{2\\}:[0-9]\\{2\\}\\'"
                value))
    (error "%s must be a timezone-qualified ISO timestamp" label))
  (let ((seconds (float-time (date-to-time value))))
    (unless (zerop (% (truncate seconds) 60))
      (error "%s must be minute aligned" label))
    (floor (/ seconds 60))))

(defun my/lifeos-schedule--timestamp (start end)
  (let* ((start-time (seconds-to-time (* start 60)))
         (end-time (seconds-to-time (* end 60)))
         (start-date (format-time-string "%Y-%m-%d %a" start-time))
         (end-date (format-time-string "%Y-%m-%d %a" end-time))
         (start-clock (format-time-string "%H:%M" start-time))
         (end-clock (format-time-string "%H:%M" end-time)))
    (if (equal start-date end-date)
        (format "<%s %s-%s>" start-date start-clock end-clock)
      (format "<%s %s>--<%s %s>"
              start-date start-clock end-date end-clock))))

(defun my/lifeos-schedule--subtree-bounds ()
  (save-excursion
    (org-back-to-heading t)
    (cons (line-beginning-position)
          (progn (org-end-of-subtree t t) (point)))))

(defun my/lifeos-schedule--accepted-markers (&optional buffer)
  (with-current-buffer (or buffer (find-file-noselect
                                   (my/lifeos-schedule--planning-file)))
    (org-with-wide-buffer
     (let (markers)
       (org-map-entries
        (lambda ()
          (when (equal (org-get-heading t t t t) "Accepted schedule")
            (push (copy-marker (point)) markers)))
        nil 'file)
       (nreverse markers)))))

(defun my/lifeos-schedule--parse-child (parent-level)
  (let* ((kind-text (org-entry-get nil "LIFEOS_PLAN_KIND"))
         (task-id (org-entry-get nil "LIFEOS_PLAN_TASK_ID"))
         (project-id (org-entry-get nil "LIFEOS_PLAN_PROJECT_ID"))
         (start-text (org-entry-get nil "LIFEOS_PLAN_START"))
         (end-text (org-entry-get nil "LIFEOS_PLAN_END"))
         (minutes-text (org-entry-get nil "LIFEOS_PLAN_MINUTES"))
         (id (org-entry-get nil "ID"))
         (title (org-get-heading t t t t))
         (kind (pcase kind-text
                 ("TASK" 'task)
                 ("PROJECT_CAPACITY" 'project-capacity)
                 (_ (error "Unknown accepted block kind: %s" kind-text))))
         (start (my/lifeos-schedule--parse-iso-minute start-text "Block start"))
         (end (my/lifeos-schedule--parse-iso-minute end-text "Block end"))
         (minutes (and minutes-text
                       (string-match-p "\\`[1-9][0-9]*\\'" minutes-text)
                       (string-to-number minutes-text))))
    (unless (= (org-outline-level) (1+ parent-level))
      (error "Accepted plan records must be direct children"))
    (unless (and id (not (string-empty-p id)))
      (error "Accepted block is missing ID"))
    (unless (and minutes (> end start) (= minutes (- end start)))
      (error "Accepted block interval contradicts LIFEOS_PLAN_MINUTES"))
    (when (and (eq kind 'task) (not task-id))
      (error "TASK accepted block is missing LIFEOS_PLAN_TASK_ID"))
    (when (and (eq kind 'project-capacity) (not project-id))
      (error "PROJECT_CAPACITY block is missing LIFEOS_PLAN_PROJECT_ID"))
    (let ((expected (my/lifeos-schedule--timestamp start end))
          (bounds (my/lifeos--entry-section-bounds)))
      (unless (and bounds
                   (save-excursion
                     (goto-char (car bounds))
                     (re-search-forward
                      (concat "^" (regexp-quote expected) "[[:space:]]*$")
                      (cdr bounds) t)))
        (error "Accepted block timestamp does not match normative interval")))
    (list :id id :kind kind :task-id task-id :project-id project-id
          :source-id (or task-id project-id) :title title :start start :end end
          :minutes minutes :role (if (eq kind 'task) 'keep 'capacity))))

(defun my/lifeos-schedule-parse-current-plan (&optional buffer)
  "Parse and validate the machine-owned accepted plan in BUFFER.
Absence is valid and represented by `:present-p' nil.  Malformed plans return
`:valid-p' nil and issues rather than silently dropping records."
  (let* ((buffer (or buffer
                     (and (file-readable-p (my/lifeos-schedule--planning-file))
                          (find-file-noselect (my/lifeos-schedule--planning-file)))))
         (markers (and buffer (my/lifeos-schedule--accepted-markers buffer))))
    (cond
     ((null markers)
      (list :present-p nil :valid-p t :blocks nil :text nil
            :fingerprint (my/lifeos-schedule--hash "")))
     ((cdr markers)
      (list :present-p t :valid-p nil
            :issues '("planning.org contains duplicate Accepted schedule subtrees")))
     (t
      (with-current-buffer buffer
        (save-excursion
          (goto-char (car markers))
          (let* ((bounds (my/lifeos-schedule--subtree-bounds))
                 (text (buffer-substring-no-properties (car bounds) (cdr bounds)))
                 (fingerprint (my/lifeos-schedule--hash text)))
            (condition-case error-data
                (let* ((parent-level (org-outline-level))
                       (metadata
                        (mapcar (lambda (property)
                                  (cons property (org-entry-get nil property)))
                                my/lifeos-schedule--plan-properties))
                       blocks (seen (make-hash-table :test #'equal)))
                  (dolist (property my/lifeos-schedule--plan-properties)
                    (unless (cdr (assoc property metadata))
                      (error "Accepted schedule is missing %s" property)))
                  (let ((horizon-start
                         (my/lifeos-schedule--parse-iso-minute
                          (cdr (assoc "LIFEOS_PLAN_HORIZON_START" metadata))
                          "Plan horizon start"))
                        (horizon-end
                         (my/lifeos-schedule--parse-iso-minute
                          (cdr (assoc "LIFEOS_PLAN_HORIZON_END" metadata))
                          "Plan horizon end")))
                    (unless (< horizon-start horizon-end)
                      (error "Accepted schedule horizon is empty or reversed"))
                    (my/lifeos-schedule--parse-iso-minute
                     (cdr (assoc "LIFEOS_PLAN_ACCEPTED_AT" metadata))
                     "Plan acceptance time"))
                  (forward-line 1)
                  (while (re-search-forward org-outline-regexp-bol (cdr bounds) t)
                    (goto-char (match-beginning 0))
                    (when (= (org-outline-level) (1+ parent-level))
                      (let ((block (my/lifeos-schedule--parse-child parent-level)))
                        (when (gethash (plist-get block :id) seen)
                          (error "Duplicate accepted block ID: %s"
                                 (plist-get block :id)))
                        (puthash (plist-get block :id) t seen)
                        (push block blocks)))
                    (forward-line 1))
                  (setq blocks
                        (sort blocks (lambda (left right)
                                       (if (= (plist-get left :start)
                                              (plist-get right :start))
                                           (string< (plist-get left :id)
                                                    (plist-get right :id))
                                         (< (plist-get left :start)
                                            (plist-get right :start))))))
                  (let ((task-ids (make-hash-table :test #'equal)) previous)
                    (dolist (block blocks)
                      (when-let* ((task-id (plist-get block :task-id)))
                        (when (gethash task-id task-ids)
                          (error "Accepted task is split or duplicated: %s" task-id))
                        (puthash task-id t task-ids))
                      (when (and previous
                                 (> (plist-get previous :end)
                                    (plist-get block :start)))
                        (error "Accepted blocks overlap: %s and %s"
                               (plist-get previous :id) (plist-get block :id)))
                      (setq previous block)))
                  (list :present-p t :valid-p t :metadata metadata :blocks blocks
                        :text text :bounds bounds :fingerprint fingerprint))
              (error
               (list :present-p t :valid-p nil :text text :bounds bounds
                     :fingerprint fingerprint
                     :issues (list (error-message-string error-data))))))))))))

(defun my/lifeos-schedule--canonical-blocks (blocks)
  (sort (copy-tree blocks)
        (lambda (left right)
          (let ((ls (plist-get left :start)) (rs (plist-get right :start)))
            (if (= ls rs)
                (string< (format "%s:%s:%s" (plist-get left :kind)
                                 (or (plist-get left :task-id) "")
                                 (or (plist-get left :project-id) ""))
                         (format "%s:%s:%s" (plist-get right :kind)
                                 (or (plist-get right :task-id) "")
                                 (or (plist-get right :project-id) "")))
              (< ls rs))))))

(defun my/lifeos-schedule-serialize-plan
    (plan-id source-fingerprint horizon-start horizon-end accepted-at blocks)
  "Return one canonical Accepted schedule subtree."
  (let ((blocks (my/lifeos-schedule--canonical-blocks blocks)))
    (concat
     "* Accepted schedule\n:PROPERTIES:\n"
     (format ":LIFEOS_PLAN_ID: %s\n" plan-id)
     (format ":LIFEOS_PLAN_SOURCE_FINGERPRINT: %s\n" source-fingerprint)
     (format ":LIFEOS_PLAN_HORIZON_START: %s\n"
             (my/lifeos-schedule--iso-time horizon-start))
     (format ":LIFEOS_PLAN_HORIZON_END: %s\n"
             (my/lifeos-schedule--iso-time horizon-end))
     (format ":LIFEOS_PLAN_ACCEPTED_AT: %s\n:END:\n"
             (my/lifeos-schedule--iso-time accepted-at))
     (mapconcat
      (lambda (block)
        (let* ((kind (plist-get block :kind))
               (start (plist-get block :start))
               (end (plist-get block :end))
               (minutes (- end start))
               (source (or (plist-get block :task-id)
                           (plist-get block :project-id)))
               (id (or (plist-get block :id)
                       (concat "lifeos-block-"
                               (substring
                                (my/lifeos-schedule--hash
                                 (format "%s:%s:%s:%s" plan-id kind source start))
                                0 16))))
               (title (replace-regexp-in-string
                       "[\n\r]+" " " (or (plist-get block :title)
                                           (if (eq kind 'task)
                                               "Planned task" "Project capacity")))))
          (concat
           (format "** %s\n:PROPERTIES:\n:ID: %s\n:LIFEOS_PLAN_KIND: %s\n"
                   title id (if (eq kind 'task) "TASK" "PROJECT_CAPACITY"))
           (if (plist-get block :task-id)
               (format ":LIFEOS_PLAN_TASK_ID: %s\n" (plist-get block :task-id)) "")
           (if (plist-get block :project-id)
               (format ":LIFEOS_PLAN_PROJECT_ID: %s\n"
                       (plist-get block :project-id)) "")
           (format ":LIFEOS_PLAN_START: %s\n:LIFEOS_PLAN_END: %s\n:LIFEOS_PLAN_MINUTES: %d\n:END:\n%s\n"
                   (my/lifeos-schedule--iso-time start)
                   (my/lifeos-schedule--iso-time end) minutes
                   (my/lifeos-schedule--timestamp start end)))))
      blocks ""))))

(defun my/lifeos-schedule--content-without-current-plan (text)
  (with-temp-buffer
    (insert text)
    (org-mode)
    (let ((markers (my/lifeos-schedule--accepted-markers (current-buffer))))
      (when (car markers)
        (goto-char (car markers))
        (pcase-let ((`(,start . ,end) (my/lifeos-schedule--subtree-bounds)))
          (delete-region start end))))
    (buffer-string)))

(defun my/lifeos-schedule-authoritative-fingerprint ()
  "Return a conservative fingerprint of authoritative planning inputs.
The accepted subtree is excluded because it has its own exact fingerprint."
  (let* ((planning (my/lifeos-schedule--planning-file))
         (files (sort (delete-dups
                       (delq nil (append (copy-sequence org-agenda-files)
                                        (list planning
                                              (expand-file-name "calendar.org"
                                                                org-directory)))))
                      #'string<))
         pieces)
    (dolist (file files)
      (when (or (file-regular-p file) (get-file-buffer file))
        (let ((text (if-let* ((buffer (get-file-buffer file)))
                        (with-current-buffer buffer
                          (buffer-substring-no-properties (point-min) (point-max)))
                      (with-temp-buffer
                        (insert-file-contents file)
                        (buffer-string)))))
          (push (concat (file-truename file) "\0"
                        (if (equal (file-truename file) (file-truename planning))
                            (my/lifeos-schedule--content-without-current-plan text)
                          text))
                pieces))))
    (my/lifeos-schedule--hash (mapconcat #'identity (nreverse pieces) "\0"))))

(defun my/lifeos-schedule-current-plan-busy (&optional start end)
  "Return valid accepted blocks as solver busy intervals overlapping START/END."
  (let ((plan (my/lifeos-schedule-parse-current-plan)))
    (unless (plist-get plan :valid-p)
      (error "Invalid Accepted schedule: %s"
             (string-join (plist-get plan :issues) "; ")))
    (vconcat
     (cl-loop for block in (plist-get plan :blocks)
              when (and (or (null start) (< (plist-get block :start) end))
                        (or (null end) (< start (plist-get block :end))))
              collect `((id . ,(concat "accepted:" (plist-get block :id)))
                        (start . ,(plist-get block :start))
                        (end . ,(plist-get block :end))
                        (kind . "accepted-plan")
                        (evidence . ((sourceId . ,(plist-get block :source-id))
                                     (kind . "accepted-plan"))))))))

(defun my/lifeos-schedule--request-fingerprint (context)
  (or (plist-get context :input-fingerprint)
      (my/lifeos-schedule-authoritative-fingerprint)))

(defun my/lifeos-schedule--replacement-boundary (requested blocks)
  (let ((boundary requested) adjustment)
    (dolist (block blocks)
      (when (and (< (plist-get block :start) boundary)
                 (< boundary (plist-get block :end)))
        (setq adjustment (format "advanced past in-progress accepted block %s"
                                 (plist-get block :id))
              boundary (plist-get block :end))))
    (list boundary adjustment)))

(defun my/lifeos-schedule-create (context blocks fixed-blocks &optional evidence)
  "Create the sole candidate from CONTEXT and complete BLOCKS."
  (when (and my/lifeos-schedule-active-candidate
             (not (my/lifeos-schedule-candidate-closed
                   my/lifeos-schedule-active-candidate)))
    (user-error "A LifeOS schedule candidate is already active"))
  (let* ((request (plist-get context :request))
         (horizon (alist-get 'horizon request))
         (plan (my/lifeos-schedule-parse-current-plan))
         (_ (unless (plist-get plan :valid-p)
              (user-error "Cannot create candidate: %s"
                          (string-join (plist-get plan :issues) "; "))))
         (requested (or (alist-get 'start horizon)
                        (floor (/ (float-time) 60))))
         (boundary (my/lifeos-schedule--replacement-boundary
                    requested (plist-get plan :blocks)))
          (context (plist-put context :current-plan plan))
          (candidate
          (my/lifeos-schedule--make-candidate
           :id (format "candidate-%d-%d" (truncate (float-time)) (random 1000000))
           :revision 0 :condition 'checking
           :input-fingerprint (my/lifeos-schedule--request-fingerprint context)
           :current-plan-fingerprint (plist-get plan :fingerprint)
           :request-id (or (plist-get context :request-id)
                           (alist-get 'requestId request))
           :horizon-start (car boundary)
           :horizon-end (or (alist-get 'end horizon)
                            (+ requested (* 28 24 60)))
           :boundary-adjustment (cadr boundary) :context context
           :blocks (copy-tree blocks) :fixed-blocks (copy-tree fixed-blocks)
           :exclusions nil :omissions nil :estimate-overrides nil :history nil)))
    (setq my/lifeos-schedule-active-candidate candidate)
    (if evidence
        (my/lifeos-schedule-apply-response candidate evidence)
      (my/lifeos-schedule-schedule-analysis candidate 0))
    candidate))

(defun my/lifeos-schedule-close (candidate)
  (unless (eq candidate my/lifeos-schedule-active-candidate)
    (user-error "Candidate is not the active schedule candidate"))
  (when (timerp my/lifeos-schedule-debounce-timer)
    (cancel-timer my/lifeos-schedule-debounce-timer))
  (setf (my/lifeos-schedule-candidate-closed candidate) t)
  (setq my/lifeos-schedule-active-candidate nil
        my/lifeos-schedule-debounce-timer nil)
  t)

(defun my/lifeos-schedule-mark-stale (&optional candidate)
  (let ((candidate (or candidate my/lifeos-schedule-active-candidate)))
    (when candidate
      (setf (my/lifeos-schedule-candidate-condition candidate) 'stale)
      (my/lifeos-schedule--refresh-buffer candidate))))

(defun my/lifeos-schedule--assert-editable (candidate)
  (unless (and (eq candidate my/lifeos-schedule-active-candidate)
               (not (my/lifeos-schedule-candidate-closed candidate)))
    (user-error "Schedule candidate is closed or inactive"))
  (when (eq (my/lifeos-schedule-candidate-condition candidate) 'stale)
    (user-error "Schedule candidate is stale; regenerate it first")))

(defun my/lifeos-schedule--snapshot-edit (candidate type source-id)
  (push (list :type type :source-id source-id
              :blocks (copy-tree (my/lifeos-schedule-candidate-blocks candidate))
              :exclusions (copy-tree
                           (my/lifeos-schedule-candidate-exclusions candidate))
              :overrides (copy-tree
                          (my/lifeos-schedule-candidate-estimate-overrides candidate)))
        (my/lifeos-schedule-candidate-history candidate)))

(defun my/lifeos-schedule--edited (candidate)
  (when-let* ((evidence (my/lifeos-schedule-candidate-evidence candidate)))
    (setf (my/lifeos-schedule-candidate-prior-evidence candidate) evidence))
  (setf (my/lifeos-schedule-candidate-evidence candidate) nil
        (my/lifeos-schedule-candidate-condition candidate) 'editing
        (my/lifeos-schedule-candidate-revision candidate)
        (1+ (my/lifeos-schedule-candidate-revision candidate)))
  (my/lifeos-schedule--refresh-buffer candidate)
  (my/lifeos-schedule-schedule-analysis candidate))

(defun my/lifeos-schedule-place (candidate source-id start)
  "Place SOURCE-ID exactly at aligned epoch-minute START."
  (my/lifeos-schedule--assert-editable candidate)
  (unless (and (integerp start) (zerop (% start 15)))
    (user-error "Exact placement start must align to 15 minutes"))
  (let ((block (seq-find (lambda (item)
                           (equal (plist-get item :source-id) source-id))
                         (my/lifeos-schedule-candidate-blocks candidate))))
    (unless (and block (eq (plist-get block :kind) 'task))
      (user-error "Select a candidate task block to place"))
    (my/lifeos-schedule--snapshot-edit candidate 'place source-id)
    (let ((minutes (plist-get block :minutes)))
      (unless (plist-get block :prior-start)
        (setq block (plist-put block :prior-start (plist-get block :start))))
      (setq block (plist-put block :start start)
            block (plist-put block :end (+ start minutes))
            block (plist-put block :role 'moved-user)))
    (my/lifeos-schedule--edited candidate)))

(defun my/lifeos-schedule-exclude (candidate source-id)
  (my/lifeos-schedule--assert-editable candidate)
  (let ((block (seq-find (lambda (item)
                           (equal (plist-get item :source-id) source-id))
                         (my/lifeos-schedule-candidate-blocks candidate))))
    (unless (and block (memq (plist-get block :kind) '(task project-capacity)))
      (user-error "Select candidate task or project capacity to exclude"))
    (my/lifeos-schedule--snapshot-edit candidate 'exclude source-id)
    (setf (my/lifeos-schedule-candidate-blocks candidate)
          (delq block (my/lifeos-schedule-candidate-blocks candidate)))
    (setf (alist-get source-id
                     (my/lifeos-schedule-candidate-estimate-overrides candidate)
                     nil 'remove #'equal)
          nil)
    (push (plist-put (copy-tree block) :role 'excluded)
          (my/lifeos-schedule-candidate-exclusions candidate))
    (my/lifeos-schedule--edited candidate)))

(defun my/lifeos-schedule-reestimate (candidate source-id minutes)
  (my/lifeos-schedule--assert-editable candidate)
  (unless (and (integerp minutes) (> minutes 0) (zerop (% minutes 15)))
    (user-error "Candidate estimate must be positive and 15-minute aligned"))
  (let ((block (seq-find (lambda (item)
                           (equal (plist-get item :source-id) source-id))
                         (my/lifeos-schedule-candidate-blocks candidate))))
    (unless block (user-error "Select candidate demand to re-estimate"))
    (my/lifeos-schedule--snapshot-edit candidate 'reestimate source-id)
    (setf (alist-get source-id
                     (my/lifeos-schedule-candidate-estimate-overrides candidate)
                     nil nil #'equal)
          minutes)
    (setq block (plist-put block :minutes minutes)
          block (plist-put block :end (+ (plist-get block :start) minutes)))
    (my/lifeos-schedule--edited candidate)))

(defun my/lifeos-schedule-undo (candidate)
  (my/lifeos-schedule--assert-editable candidate)
  (let ((edit (pop (my/lifeos-schedule-candidate-history candidate))))
    (unless edit (user-error "No candidate edit to undo"))
    (setf (my/lifeos-schedule-candidate-blocks candidate)
          (plist-get edit :blocks)
          (my/lifeos-schedule-candidate-exclusions candidate)
          (plist-get edit :exclusions)
          (my/lifeos-schedule-candidate-estimate-overrides candidate)
          (plist-get edit :overrides))
    (my/lifeos-schedule--edited candidate)))

(defun my/lifeos-schedule-schedule-analysis (candidate &optional delay)
  (my/lifeos-schedule--assert-editable candidate)
  (when (timerp my/lifeos-schedule-debounce-timer)
    (cancel-timer my/lifeos-schedule-debounce-timer))
  (setq my/lifeos-schedule-debounce-timer
        (run-with-idle-timer (or delay my/lifeos-schedule-debounce-delay) nil
                             #'my/lifeos-schedule--send-analysis candidate)))

(defun my/lifeos-schedule--send-analysis (candidate)
  (setq my/lifeos-schedule-debounce-timer nil)
  (when (and (eq candidate my/lifeos-schedule-active-candidate)
             (not (my/lifeos-schedule-candidate-closed candidate))
             (not (eq (my/lifeos-schedule-candidate-condition candidate) 'stale)))
    (let ((request-id (format "schedule-%d" (cl-incf my/lifeos-schedule-request-sequence))))
      (setf (my/lifeos-schedule-candidate-condition candidate) 'checking
            (my/lifeos-schedule-candidate-pending-request-id candidate) request-id)
      (my/lifeos-schedule--refresh-buffer candidate)
      (funcall my/lifeos-schedule-analysis-function
               (list :candidate candidate
                     :candidate-id (my/lifeos-schedule-candidate-id candidate)
                     :revision (my/lifeos-schedule-candidate-revision candidate)
                     :input-fingerprint
                     (my/lifeos-schedule-candidate-input-fingerprint candidate)
                     :request-id request-id
                     :blocks (copy-tree
                              (my/lifeos-schedule-candidate-blocks candidate))
                     :fixed-blocks (copy-tree
                                    (my/lifeos-schedule-candidate-fixed-blocks candidate))
                     :exclusions (copy-tree
                                  (my/lifeos-schedule-candidate-exclusions candidate))
                      :estimate-overrides (copy-tree
                                           (my/lifeos-schedule-candidate-estimate-overrides
                                            candidate))
                     :horizon-start
                     (my/lifeos-schedule-candidate-horizon-start candidate)
                     :horizon-end
                     (my/lifeos-schedule-candidate-horizon-end candidate))
               (lambda (response)
                 (my/lifeos-schedule-apply-response candidate response))))))

(defun my/lifeos-schedule--overlap-p (left right)
  (and (< (plist-get left :start) (plist-get right :end))
       (< (plist-get right :start) (plist-get left :end))))

(defun my/lifeos-schedule--verify-blocks (blocks fixed &optional horizon-start horizon-end)
  (let ((task-ids (make-hash-table :test #'equal)) conflicts)
    (dolist (block blocks)
      (unless (memq (plist-get block :kind) '(task project-capacity))
        (push (format "Unknown candidate block kind for %s"
                      (plist-get block :source-id)) conflicts))
      (when-let* ((task-id (plist-get block :task-id)))
        (when (gethash task-id task-ids)
          (push (format "Candidate task is split or duplicated: %s" task-id)
                conflicts))
        (puthash task-id t task-ids))
      (unless (and (integerp (plist-get block :start))
                   (integerp (plist-get block :end))
                   (< (plist-get block :start) (plist-get block :end))
                   (= (- (plist-get block :end) (plist-get block :start))
                      (plist-get block :minutes)))
        (push (format "Malformed interval for %s" (plist-get block :source-id))
              conflicts))
      (when (and horizon-start
                 (< (plist-get block :start) horizon-start))
        (push (format "%s begins before the replacement horizon"
                      (plist-get block :source-id)) conflicts))
      (when (and horizon-end (> (plist-get block :end) horizon-end))
        (push (format "%s ends after the replacement horizon"
                      (plist-get block :source-id)) conflicts))
      (dolist (other (append blocks fixed))
        (when (and (not (eq block other))
                   (my/lifeos-schedule--overlap-p block other))
          (push (format "%s overlaps %s" (plist-get block :source-id)
                        (or (plist-get other :source-id) "fixed work"))
                conflicts))))
    (delete-dups (nreverse conflicts))))

(defun my/lifeos-schedule--demand-kind (block)
  (if (eq (plist-get block :kind) 'project-capacity)
      "PROJECT_CAPACITY"
    "TASK"))

(defun my/lifeos-schedule--candidate-demand-json (block)
  (if (eq (plist-get block :kind) 'project-capacity)
      `((kind . "PROJECT_CAPACITY")
        (projectId . ,(plist-get block :source-id)))
    `((kind . "TASK") (taskId . ,(plist-get block :source-id)))))

(defun my/lifeos-schedule--candidate-seeds (candidate request)
  "Return strict v3 current-plan seeds for CANDIDATE and REQUEST."
  (let* ((plan (plist-get (my/lifeos-schedule-candidate-context candidate)
                          :current-plan))
         (excluded (mapcar (lambda (block) (plist-get block :source-id))
                           (my/lifeos-schedule-candidate-exclusions candidate)))
         (overrides (my/lifeos-schedule-candidate-estimate-overrides candidate))
         (start (my/lifeos-schedule-candidate-horizon-start candidate))
         (end (my/lifeos-schedule-candidate-horizon-end candidate))
         (capacity-index (make-hash-table :test #'equal))
         seeds)
    (dolist (block (plist-get plan :blocks) (vconcat (nreverse seeds)))
      (let* ((source-id (plist-get block :source-id))
             (kind (plist-get block :kind))
             (block-start (plist-get block :start)))
        (when (and (not (member source-id excluded))
                   (>= block-start start) (< block-start end))
          (if (eq kind 'task)
              (when-let* ((task (seq-find
                                 (lambda (item)
                                   (equal (alist-get 'id item) source-id))
                                 (append (alist-get 'tasks request) nil)))
                          ((equal (alist-get 'workType task) "explicit")))
                (let ((minutes (or (alist-get source-id overrides nil nil #'equal)
                                   (alist-get 'durationMinutes task))))
                  (when (and (integerp minutes) (<= (+ block-start minutes) end))
                    (push `((kind . "TASK") (taskId . ,source-id)
                            (start . ,block-start) (end . ,(+ block-start minutes)))
                          seeds))))
            (when-let* ((project (seq-find
                                  (lambda (item)
                                    (equal (alist-get 'id item) source-id))
                                  (append (alist-get 'projects request) nil)))
                        ((equal (alist-get 'definitionStatus project) "COARSE")))
              (let* ((index (gethash source-id capacity-index 0))
                     (total (or (alist-get source-id overrides nil nil #'equal)
                                (alist-get 'virtualEffortMinutes project)))
                     (chunk (alist-get 'planningChunkMinutes project))
                     (remaining (and (integerp total) (integerp chunk)
                                     (- total (* index chunk))))
                     (minutes (and remaining (> remaining 0)
                                   (min chunk remaining))))
                (puthash source-id (1+ index) capacity-index)
                (when (and minutes (<= (+ block-start minutes) end))
                  (push `((kind . "PROJECT_CAPACITY") (projectId . ,source-id)
                          (start . ,block-start) (end . ,(+ block-start minutes)))
                        seeds))))))))))

(defun my/lifeos-schedule--normalized-candidate-request (analysis-request)
  "Build a strict v3 request from captured Portfolio input and ANALYSIS-REQUEST."
  (let* ((candidate (plist-get analysis-request :candidate))
         (request (copy-tree
                   (plist-get (my/lifeos-schedule-candidate-context candidate)
                              :request)))
         (request-id (plist-get analysis-request :request-id))
         (exclusions (my/lifeos-schedule-candidate-exclusions candidate))
         (all-demand (append (my/lifeos-schedule-candidate-blocks candidate)
                             exclusions))
         (overrides (my/lifeos-schedule-candidate-estimate-overrides candidate))
         exact override-json)
    (dolist (block (my/lifeos-schedule-candidate-blocks candidate))
      (when (and (eq (plist-get block :kind) 'task)
                 (eq (plist-get block :role) 'moved-user))
        (push `((taskId . ,(plist-get block :source-id))
                (start . ,(plist-get block :start))) exact)))
    (dolist (override overrides)
      (when-let* ((block (seq-find
                          (lambda (item) (equal (plist-get item :source-id)
                                                (car override)))
                          all-demand)))
        (push (append (my/lifeos-schedule--candidate-demand-json block)
                      `((durationMinutes . ,(cdr override))))
              override-json)))
    (setf (alist-get 'protocolVersion request) "lifeos-planning/v3"
          (alist-get 'requestId request) request-id
          (alist-get 'horizon request)
          `((start . ,(my/lifeos-schedule-candidate-horizon-start candidate))
            (end . ,(my/lifeos-schedule-candidate-horizon-end candidate)))
          (alist-get 'busy request)
          (vconcat
           (seq-remove (lambda (interval)
                         (equal (alist-get 'kind interval) "accepted-plan"))
                       (append (alist-get 'busy request) nil)))
          (alist-get 'scenario request) :null
          (alist-get 'negotiationQueries request) []
          (alist-get 'candidate request)
          `((candidateId . ,(my/lifeos-schedule-candidate-id candidate))
            (revision . ,(my/lifeos-schedule-candidate-revision candidate))
            (capturedInputFingerprint
             . ,(my/lifeos-schedule-candidate-input-fingerprint candidate))
            (exactPlacements . ,(vconcat (nreverse exact)))
            (exclusions . ,(vconcat
                            (mapcar #'my/lifeos-schedule--candidate-demand-json
                                    exclusions)))
            (estimateOverrides . ,(vconcat (nreverse override-json)))
            (currentPlanSeeds
             . ,(my/lifeos-schedule--candidate-seeds candidate request))))
    request))

(defun my/lifeos-schedule--candidate-identity (request)
  (let ((candidate (alist-get 'candidate request)))
    `((candidateId . ,(alist-get 'candidateId candidate))
      (revision . ,(alist-get 'revision candidate))
      (capturedInputFingerprint . ,(alist-get 'capturedInputFingerprint candidate))
      (normalizedRequestId . ,(alist-get 'requestId request)))))

(defun my/lifeos-schedule--candidate-response-verification-errors (request response)
  "Independently check v3 candidate attribution and edits in RESPONSE."
  (let* ((candidate (alist-get 'candidate request))
         (baseline (alist-get 'baseline response))
         (evidence (and baseline (alist-get 'candidateEvidence baseline)))
         (placements (and baseline (alist-get 'placements baseline)))
         (omissions (and baseline (alist-get 'omissions baseline)))
         (feasibility (and baseline (alist-get 'feasibility baseline)))
         (identity (my/lifeos-schedule--candidate-identity request))
         errors)
    (when-let* ((error (my/lifeos-solver--response-validation-error
                        response (alist-get 'requestId request) identity)))
      (push error errors))
    (unless (and (my/lifeos-solver--json-object-p evidence)
                 (my/lifeos-solver--required-fields-p
                  evidence '(identity exactPlacementTaskIds excludedSourceIds
                                      estimateOverrideSourceIds seed deadlineStatus
                                      safetyStatus intentionStatus estimateConfidenceStatus
                                      capacityStatus placedCapacityMinutes
                                      omittedCapacityMinutes))
                 (equal (alist-get 'identity evidence) identity)
                 (member (alist-get 'deadlineStatus evidence)
                         '("SATISFIED" "CONFLICT" "UNKNOWN"))
                 (member (alist-get 'safetyStatus evidence)
                         '("SATISFIED" "AT_RISK" "UNKNOWN"))
                 (member (alist-get 'intentionStatus evidence)
                         '("SATISFIED" "AT_RISK" "UNKNOWN"))
                 (member (alist-get 'estimateConfidenceStatus evidence)
                         '("HIGH" "MEDIUM" "LOW" "UNKNOWN"))
                 (member (alist-get 'capacityStatus evidence)
                         '("SATISFIED" "AT_RISK" "UNKNOWN"))
                 (integerp (alist-get 'placedCapacityMinutes evidence))
                 (integerp (alist-get 'omittedCapacityMinutes evidence)))
      (push "Candidate evidence is malformed or its identity does not match" errors))
    (when evidence
      (dolist (pair `((exactPlacementTaskIds . ,(mapcar
                                                  (lambda (item) (alist-get 'taskId item))
                                                  (append (alist-get 'exactPlacements candidate) nil)))
                       (excludedSourceIds . ,(mapcar
                                              (lambda (item) (or (alist-get 'taskId item)
                                                                 (alist-get 'projectId item)))
                                              (append (alist-get 'exclusions candidate) nil)))
                       (estimateOverrideSourceIds . ,(mapcar
                                                      (lambda (item) (or (alist-get 'taskId item)
                                                                         (alist-get 'projectId item)))
                                                      (append (alist-get 'estimateOverrides candidate) nil)))))
        (unless (equal (sort (copy-sequence (alist-get (car pair) evidence)) #'string<)
                       (sort (copy-sequence (cdr pair)) #'string<))
          (push (format "Candidate evidence %s does not match the request" (car pair))
                errors))))
    (unless (member feasibility '("PROVEN FEASIBLE" "PROVEN INFEASIBLE"))
      (push "Candidate feasibility is not proven" errors))
    (dolist (placement placements)
      (let* ((task-id (alist-get 'taskId placement))
             (task (seq-find (lambda (item) (equal (alist-get 'id item) task-id))
                             (append (alist-get 'tasks request) nil)))
             (virtual (and task (equal (alist-get 'workType task) "virtual")))
             (expected-source (and task (if virtual (alist-get 'projectId task) task-id))))
        (unless (and (my/lifeos-solver--required-fields-p
                      placement '(taskId projectId demandKind sourceId start end kind
                                           rationale estimateConfidence))
                     task
                     (equal (alist-get 'sourceId placement) expected-source)
                     (equal (alist-get 'demandKind placement)
                            (if virtual "PROJECT_CAPACITY" "TASK"))
                     (member (alist-get 'rationale placement)
                             '("fixed-commitment" "exact-user-placement"
                               "current-plan-seed-kept" "current-plan-seed-moved"
                               "solver-selected")))
          (push (format "Placement attribution is invalid for %s" task-id) errors))))
    (dolist (omission omissions)
      (unless (and (my/lifeos-solver--json-object-p omission)
                   (my/lifeos-solver--required-fields-p
                    omission '(demandKind sourceId taskId projectId durationMinutes
                                          rationale deadline estimateConfidence))
                   (member (alist-get 'demandKind omission)
                           '("TASK" "PROJECT_CAPACITY"))
                   (member (alist-get 'rationale omission)
                           '("user-excluded" "solver-omitted" "unresolved-input")))
        (push "Candidate omission is malformed" errors)))
    (dolist (exact (append (alist-get 'exactPlacements candidate) nil))
      (when (equal feasibility "PROVEN FEASIBLE")
        (unless (seq-find (lambda (placement)
                            (and (equal (alist-get 'taskId placement)
                                        (alist-get 'taskId exact))
                                 (= (alist-get 'start placement) (alist-get 'start exact))
                                 (equal (alist-get 'rationale placement)
                                        "exact-user-placement")))
                          placements)
          (push (format "Exact placement was not honored for %s"
                        (alist-get 'taskId exact)) errors))))
    (dolist (excluded (append (alist-get 'exclusions candidate) nil))
      (let ((source (or (alist-get 'taskId excluded) (alist-get 'projectId excluded))))
        (when (seq-find (lambda (placement)
                          (equal (alist-get 'sourceId placement) source))
                        placements)
          (push (format "Excluded demand was placed: %s" source) errors))
        (unless (seq-find (lambda (omission)
                            (and (equal (alist-get 'sourceId omission) source)
                                 (equal (alist-get 'rationale omission) "user-excluded")))
                          omissions)
          (push (format "Excluded demand has no matching omission: %s" source) errors))))
    (nreverse errors)))

(defun my/lifeos-schedule--block-from-placement (placement request context plan)
  (let* ((task-id (alist-get 'taskId placement))
         (task (seq-find (lambda (item) (equal (alist-get 'id item) task-id))
                         (append (alist-get 'tasks request) nil)))
         (capacity (equal (alist-get 'demandKind placement) "PROJECT_CAPACITY"))
         (source-id (alist-get 'sourceId placement))
         (old (seq-find (lambda (block) (equal (plist-get block :source-id) source-id))
                        (plist-get plan :blocks)))
         (rationale (alist-get 'rationale placement))
         (role (cond ((equal rationale "exact-user-placement") 'moved-user)
                     ((equal rationale "current-plan-seed-kept")
                      (if capacity 'capacity 'keep))
                     ((equal rationale "current-plan-seed-moved")
                      (if capacity 'capacity 'moved-plan))
                     (capacity 'capacity) (t 'new))))
    (list :kind (if capacity 'project-capacity 'task) :role role
          :source-id source-id :task-id (unless capacity task-id)
          :project-id (alist-get 'projectId placement)
          :start (alist-get 'start placement) :end (alist-get 'end placement)
          :minutes (- (alist-get 'end placement) (alist-get 'start placement))
          :source-minutes (and task (alist-get 'durationMinutes task))
          :prior-start (and old (not (= (alist-get 'start placement)
                                        (plist-get old :start)))
                            (plist-get old :start))
          :title (my/lifeos-solver--title context source-id)
          :marker (and (plist-get context :source-markers)
                       (gethash source-id (plist-get context :source-markers)))
          :rationale rationale)))

(defun my/lifeos-schedule--omission-from-response (omission context)
  (let ((source-id (alist-get 'sourceId omission)))
    (list :kind (if (equal (alist-get 'demandKind omission) "PROJECT_CAPACITY")
                    'project-capacity 'task)
          :role (if (equal (alist-get 'rationale omission) "user-excluded")
                    'excluded 'omitted)
          :source-id source-id :task-id (alist-get 'taskId omission)
          :project-id (alist-get 'projectId omission)
          :start nil :end nil :minutes (or (alist-get 'durationMinutes omission) 0)
          :title (my/lifeos-solver--title context source-id)
          :marker (and (plist-get context :source-markers)
                       (gethash source-id (plist-get context :source-markers)))
          :rationale (alist-get 'rationale omission))))

(defun my/lifeos-schedule--translate-candidate-response (analysis-request request response)
  (let* ((candidate (plist-get analysis-request :candidate))
         (context (my/lifeos-schedule-candidate-context candidate))
         (plan (plist-get context :current-plan))
         (baseline (alist-get 'baseline response))
         (candidate-evidence (alist-get 'candidateEvidence baseline))
         (feasibility (alist-get 'feasibility baseline))
         (errors (my/lifeos-schedule--candidate-response-verification-errors
                  request response))
         (solver-blocks
          (mapcar (lambda (placement)
                    (my/lifeos-schedule--block-from-placement
                     placement request context plan))
                  (seq-filter (lambda (placement)
                                (equal (alist-get 'kind placement) "proposed"))
                              (alist-get 'placements baseline))))
         (omissions (mapcar (lambda (omission)
                              (my/lifeos-schedule--omission-from-response
                               omission context))
                            (alist-get 'omissions baseline)))
         (hard-conflicts (mapcar (lambda (conflict) (alist-get 'message conflict))
                                 (alist-get 'conflicts baseline))))
    (when (and (equal feasibility "PROVEN INFEASIBLE") (null hard-conflicts))
      (setq hard-conflicts '("Solver proved the candidate infeasible")))
    (append analysis-request
            (list :complete (member feasibility
                                    '("PROVEN FEASIBLE" "PROVEN INFEASIBLE"))
                  :verified (null errors) :verification-errors errors
                  :hard-conflicts hard-conflicts
                  :safety-pass (equal (alist-get 'safetyStatus candidate-evidence)
                                      "SATISFIED")
                  :reserve-pass t
                  :intention-pass (not (equal (alist-get 'intentionStatus candidate-evidence)
                                              "AT_RISK"))
                  :confidence-pass
                  (not (equal (alist-get 'estimateConfidenceStatus candidate-evidence) "LOW"))
                  :capacity-pass (not (equal (alist-get 'capacityStatus candidate-evidence)
                                             "AT_RISK"))
                  :replace-solver-blocks (equal feasibility "PROVEN FEASIBLE")
                  :solver-blocks solver-blocks
                  :solver-omissions
                  (seq-remove (lambda (block) (eq (plist-get block :role) 'excluded))
                              omissions)
                  :raw-response response))))

(defun my/lifeos-schedule--analysis-failure (analysis-request message)
  (append analysis-request
          (list :complete nil :verified nil :verification-errors (list message)
                :hard-conflicts nil :safety-pass nil :reserve-pass nil
                :intention-pass nil :confidence-pass nil :capacity-pass nil)))

(defun my/lifeos-schedule--analysis-process-timeout (process)
  (when (process-live-p process)
    (process-put process 'lifeos-schedule-timed-out t)
    (funcall (process-get process 'lifeos-schedule-callback)
             (my/lifeos-schedule--analysis-failure
              (process-get process 'lifeos-schedule-analysis-request)
              "Solver process timed out"))
    (delete-process process)))

(defun my/lifeos-schedule--analysis-process-sentinel (process _event)
  (when (memq (process-status process) '(exit signal))
    (when-let* ((timer (process-get process 'lifeos-schedule-timer)))
      (cancel-timer timer))
    (unless (process-get process 'lifeos-schedule-timed-out)
      (let* ((analysis-request (process-get process 'lifeos-schedule-analysis-request))
             (request (process-get process 'lifeos-schedule-normalized-request))
             (callback (process-get process 'lifeos-schedule-callback))
             (stderr-buffer (process-get process 'lifeos-schedule-stderr-buffer))
             (stderr (if (buffer-live-p stderr-buffer)
                         (with-current-buffer stderr-buffer (string-trim (buffer-string))) "")))
        (condition-case error-data
            (let* ((raw (with-current-buffer (process-buffer process)
                          (string-trim (buffer-string))))
                   (response (json-parse-string raw :object-type 'alist :array-type 'list
                                                :null-object nil :false-object nil)))
              (if (and (zerop (process-exit-status process))
                       (equal (alist-get 'status response) "ok"))
                  (funcall callback
                           (my/lifeos-schedule--translate-candidate-response
                            analysis-request request response))
                (funcall callback
                         (my/lifeos-schedule--analysis-failure
                          analysis-request
                          (string-join
                           (delq nil (list
                                      (format "Solver returned %s"
                                              (or (alist-get 'status response) "an error"))
                                      (when-let* ((errors (alist-get 'errors response)))
                                        (mapconcat
                                         (lambda (item)
                                           (format "%s: %s" (alist-get 'path item)
                                                   (alist-get 'message item)))
                                         errors "; "))
                                           (unless (string-empty-p stderr) stderr)))
                           ": ")))))
          (error
           (funcall callback
                    (my/lifeos-schedule--analysis-failure
                     analysis-request (error-message-string error-data)))))))
    (setq my/lifeos-schedule-analysis-processes
          (delq process my/lifeos-schedule-analysis-processes))
    (when (buffer-live-p (process-buffer process)) (kill-buffer (process-buffer process)))
    (when (buffer-live-p (process-get process 'lifeos-schedule-stderr-buffer))
      (kill-buffer (process-get process 'lifeos-schedule-stderr-buffer)))))

(defun my/lifeos-schedule--solver-analysis (analysis-request callback)
  "Submit ANALYSIS-REQUEST to the strict v3 solver without replacing Portfolio work."
  (let* ((request (my/lifeos-schedule--normalized-candidate-request analysis-request))
         (request-id (alist-get 'requestId request))
         (buffer (generate-new-buffer (format " *LifeOS Schedule Solver %s*" request-id)))
         (stderr-buffer
          (generate-new-buffer (format " *LifeOS Schedule Solver stderr %s*" request-id)))
         (process (make-process
                   :name (format "lifeos-schedule-solver-%s" request-id)
                   :buffer buffer :stderr stderr-buffer
                   :command (or my/lifeos-solver-command
                                (my/lifeos-solver--default-command))
                   :connection-type 'pipe :coding 'utf-8-unix :noquery t
                   :sentinel #'my/lifeos-schedule--analysis-process-sentinel)))
    (process-put process 'lifeos-schedule-analysis-request analysis-request)
    (process-put process 'lifeos-schedule-normalized-request request)
    (process-put process 'lifeos-schedule-callback callback)
    (process-put process 'lifeos-schedule-stderr-buffer stderr-buffer)
    (process-put process 'lifeos-schedule-timer
                 (run-at-time (my/lifeos-solver--process-timeout-seconds request)
                              nil #'my/lifeos-schedule--analysis-process-timeout process))
    (push process my/lifeos-schedule-analysis-processes)
    (process-send-string process (json-serialize request))
    (process-send-eof process)
    process))

(defun my/lifeos-schedule--local-analysis (request callback)
  (let ((conflicts (my/lifeos-schedule--verify-blocks
                    (plist-get request :blocks) (plist-get request :fixed-blocks)
                    (plist-get request :horizon-start)
                    (plist-get request :horizon-end))))
    (funcall callback
             (append request
                      (list :complete nil
                            :verified nil :hard-conflicts conflicts
                            :safety-pass t :reserve-pass t :intention-pass t
                            :confidence-pass t :capacity-pass t
                            :diagnostics
                            '("Local overlap checks are diagnostic only; solver proof is required."))))))

(defun my/lifeos-schedule--portfolio-candidate-evidence
    (candidate result context)
  "Return initial evidence for CANDIDATE from exact Portfolio RESULT/CONTEXT."
  (let* ((state (my/lifeos-solver--portfolio-evidence-state result context))
         (status (my/lifeos-schedule-portfolio-status result context))
         (local-conflicts
          (my/lifeos-schedule--verify-blocks
           (my/lifeos-schedule-candidate-blocks candidate)
           (my/lifeos-schedule-candidate-fixed-blocks candidate)
           (my/lifeos-schedule-candidate-horizon-start candidate)
           (my/lifeos-schedule-candidate-horizon-end candidate)))
         (request-id "portfolio-seed"))
    (setf (my/lifeos-schedule-candidate-pending-request-id candidate) request-id)
    (list :candidate-id (my/lifeos-schedule-candidate-id candidate)
          :revision (my/lifeos-schedule-candidate-revision candidate)
          :input-fingerprint
          (my/lifeos-schedule-candidate-input-fingerprint candidate)
          :request-id request-id
          :complete (and (equal state "CURRENT")
                         (not (equal status "NEED INFO")))
          :verified (and (equal state "CURRENT") (null local-conflicts))
          :hard-conflicts (append local-conflicts
                                  (and (equal status "DOES NOT FIT")
                                       '("Portfolio proof is infeasible")))
          :safety-pass (not (equal status "AT RISK"))
          :reserve-pass t :intention-pass t :confidence-pass t :capacity-pass t
          :portfolio-result result)))

(defun my/lifeos-schedule-apply-response (candidate response)
  "Publish RESPONSE only when every candidate identity and proof gate matches."
  (let ((matches
         (and (listp response)
              (eq candidate my/lifeos-schedule-active-candidate)
              (not (my/lifeos-schedule-candidate-closed candidate))
              (equal (plist-get response :candidate-id)
                     (my/lifeos-schedule-candidate-id candidate))
              (= (or (plist-get response :revision) -1)
                 (my/lifeos-schedule-candidate-revision candidate))
              (equal (plist-get response :input-fingerprint)
                     (my/lifeos-schedule-candidate-input-fingerprint candidate))
              (equal (plist-get response :request-id)
                     (my/lifeos-schedule-candidate-pending-request-id candidate))
              (plist-get response :complete)
              (plist-get response :verified))))
    (when matches
      (setf (my/lifeos-schedule-candidate-evidence candidate) response
            (my/lifeos-schedule-candidate-condition candidate) 'current)
      (when (plist-get response :replace-solver-blocks)
        (setf (my/lifeos-schedule-candidate-blocks candidate)
              (plist-get response :solver-blocks)))
      (when (plist-member response :solver-omissions)
        (setf (my/lifeos-schedule-candidate-omissions candidate)
              (plist-get response :solver-omissions)))
      (my/lifeos-schedule--refresh-buffer candidate))
    matches))

(defun my/lifeos-schedule-status (candidate)
  (let ((evidence (my/lifeos-schedule-candidate-evidence candidate)))
    (cond
     ((or (not (eq (my/lifeos-schedule-candidate-condition candidate) 'current))
          (not evidence) (not (plist-get evidence :complete))
          (not (plist-get evidence :verified))
          (seq-some (lambda (key) (not (plist-member evidence key)))
                    '(:hard-conflicts :safety-pass :reserve-pass :intention-pass
                      :confidence-pass :capacity-pass)))
      'need-info)
     ((plist-get evidence :hard-conflicts) 'does-not-fit)
     ((seq-some (lambda (key) (not (plist-get evidence key)))
                '(:safety-pass :reserve-pass :intention-pass
                  :confidence-pass :capacity-pass))
      'at-risk)
     (t 'fits))))

(defun my/lifeos-schedule-acceptable-p (candidate)
  (let ((evidence (my/lifeos-schedule-candidate-evidence candidate)))
    (and (eq (my/lifeos-schedule-candidate-condition candidate) 'current)
         (memq (my/lifeos-schedule-status candidate) '(fits at-risk))
         (equal (plist-get evidence :candidate-id)
                (my/lifeos-schedule-candidate-id candidate))
         (= (or (plist-get evidence :revision) -1)
            (my/lifeos-schedule-candidate-revision candidate))
         (equal (plist-get evidence :input-fingerprint)
                (my/lifeos-schedule-candidate-input-fingerprint candidate))
         (equal (plist-get evidence :request-id)
                (my/lifeos-schedule-candidate-pending-request-id candidate)))))

(defun my/lifeos-schedule--status-text (status)
  (pcase status
    ('need-info "NEED INFO") ('does-not-fit "DOES NOT FIT")
    ('at-risk "AT RISK") ('fits "FITS") (_ "NEED INFO")))

(defun my/lifeos-schedule-portfolio-status (result context)
  "Project RESULT and CONTEXT to the bounded planning status vocabulary."
  (let* ((state (my/lifeos-solver--portfolio-evidence-state result context))
         (portfolio (and result (alist-get 'baselinePortfolio result)))
         (global (and portfolio (alist-get 'globalResult portfolio)))
         (definition (and portfolio (alist-get 'definitionStatus portfolio)))
         (feasibility (and portfolio (alist-get 'feasibility portfolio)))
         (safety (and portfolio (alist-get 'safety portfolio))))
    (cond
     ((or (not (equal state "CURRENT"))
          (not (equal definition "COMPLETE"))
          (not global)
          (not (member feasibility '("PROVEN FEASIBLE" "PROVEN INFEASIBLE"))))
      "NEED INFO")
     ((equal feasibility "PROVEN INFEASIBLE") "DOES NOT FIT")
     ((or (not (equal safety "SAFE"))
          (seq-some
           (lambda (project)
             (or (let ((margin (alist-get 'safetyMarginMinutes project)))
                   (and (numberp margin) (< margin 0)))
                 (member (alist-get 'portfolioStatus project)
                         '("CONFLICT-INVOLVED" "AT-RISK"))))
           (alist-get 'projectResults portfolio)))
      "AT RISK")
     (t "FITS"))))

(defun my/lifeos-schedule--block-label (block)
  (pcase (plist-get block :role)
    ('fixed "[FIXED]") ('keep "[KEEP]") ('new "[NEW]")
    ('moved-user "[MOVED: USER]") ('moved-plan "[MOVED: PLAN]")
    ('capacity "[CAP]") ('excluded "[EXCL]") ('omitted "[OMIT]")
    (_ (if (eq (plist-get block :kind) 'project-capacity) "[CAP]" "[NEW]"))))

(defun my/lifeos-schedule--selection ()
  (get-text-property (point) 'lifeos-schedule-block))

(defun my/lifeos-schedule--insert-block (block)
  (let ((start (point)))
    (insert (format "%s  %-14s %-44s %4dm\n"
                    (if (numberp (plist-get block :start))
                        (format-time-string
                         "%H:%M" (seconds-to-time (* 60 (plist-get block :start))))
                      "--:--")
                    (my/lifeos-schedule--block-label block)
                    (or (plist-get block :title) (plist-get block :source-id) "Untitled")
                    (plist-get block :minutes)))
    (when-let* ((prior (plist-get block :prior-start)))
      (insert (format "       previously %s\n"
                       (my/lifeos-schedule--format-minute prior))))
    (add-text-properties start (point)
                         (list 'lifeos-schedule-block block
                               'lifeos-schedule-source
                               (plist-get block :source-id)
                               'mouse-face 'highlight 'rear-nonsticky t))))

(defun my/lifeos-schedule-render (&optional candidate)
  "Render CANDIDATE in the current workbench buffer."
  (let* ((candidate (or candidate my/lifeos-schedule-buffer-candidate
                        my/lifeos-schedule-active-candidate))
         (selected (and (my/lifeos-schedule--selection)
                        (plist-get (my/lifeos-schedule--selection) :source-id)))
         (old-positions (my/lifeos-schedule--selectable-positions))
         (old-index (or (cl-position-if (lambda (position) (<= (point) position))
                                        old-positions)
                        (and old-positions (1- (length old-positions)))))
         (window-start (and (get-buffer-window (current-buffer))
                            (window-start (get-buffer-window (current-buffer)))))
         (inhibit-read-only t))
    (unless candidate (user-error "No active schedule candidate"))
    (erase-buffer)
    (setq-local my/lifeos-schedule-buffer-candidate candidate)
    (insert (format "LifeOS Schedule Candidate             %s | %s\n"
                    (upcase (symbol-name
                             (my/lifeos-schedule-candidate-condition candidate)))
                    (my/lifeos-schedule--status-text
                     (my/lifeos-schedule-status candidate))))
    (insert (format "Horizon: %s - %s\nEvidence: %s\n"
                    (my/lifeos-schedule--format-minute
                     (my/lifeos-schedule-candidate-horizon-start candidate))
                    (my/lifeos-schedule--format-minute
                     (my/lifeos-schedule-candidate-horizon-end candidate))
                    (if (my/lifeos-schedule-candidate-evidence candidate)
                        "current" (if (my/lifeos-schedule-candidate-prior-evidence candidate)
                                      "prior context only" "awaiting proof"))))
    (when-let* ((adjustment
                 (my/lifeos-schedule-candidate-boundary-adjustment candidate)))
      (insert (format "Boundary: %s\n" adjustment)))
    (insert "Controls: n/p blocks, RET details, v source, m place, x exclude, e estimate, u undo, r regenerate, a accept, d discard, R restore, h help, q quit.\n\n")
    (insert "Schedule\n========\n")
    (let ((blocks (my/lifeos-schedule--canonical-blocks
                   (append (copy-tree
                            (my/lifeos-schedule-candidate-fixed-blocks candidate))
                           (copy-tree
                            (my/lifeos-schedule-candidate-blocks candidate)))))
          previous-day)
      (dolist (block blocks)
        (let ((day (format-time-string "%a %b %d"
                                       (seconds-to-time (* 60 (plist-get block :start))))))
          (unless (equal day previous-day)
            (insert (if previous-day "\n" "") day "\n")
            (setq previous-day day)))
        (my/lifeos-schedule--insert-block block)))
    (insert "\nOmissions\n=========\n")
    (dolist (block (append (my/lifeos-schedule-candidate-exclusions candidate)
                           (my/lifeos-schedule-candidate-omissions candidate)))
      (my/lifeos-schedule--insert-block block)
      (insert (if (eq (plist-get block :role) 'excluded)
                  "       User excluded; source task or project unchanged\n"
                "       Solver omitted; review consequence evidence\n")))
    (unless (or (my/lifeos-schedule-candidate-exclusions candidate)
                (my/lifeos-schedule-candidate-omissions candidate))
      (insert "None.\n"))
    (let* ((blocks (my/lifeos-schedule-candidate-blocks candidate))
           (count (lambda (role) (seq-count (lambda (block)
                                              (eq (plist-get block :role) role))
                                            blocks))))
      (insert "\nConsequences\n============\n")
      (insert (format "Hard feasibility: %s\n"
                      (if (eq (my/lifeos-schedule-status candidate) 'does-not-fit)
                          "fails" "passes or awaiting proof")))
      (insert (format "Keep %d | Move %d | Add %d | Remove 0 | Exclude %d | Omit %d\n"
                      (funcall count 'keep)
                      (+ (funcall count 'moved-user) (funcall count 'moved-plan))
                      (funcall count 'new)
                      (length (my/lifeos-schedule-candidate-exclusions candidate))
                      (length (my/lifeos-schedule-candidate-omissions candidate)))))
    (goto-char (point-min))
    (when selected
      (let ((position (text-property-any (point-min) (point-max)
                                         'lifeos-schedule-source selected)))
        (when position (goto-char position))))
    (unless (my/lifeos-schedule--selection)
      (when-let* ((positions (my/lifeos-schedule--selectable-positions)))
        (goto-char (nth (min (or old-index 0) (1- (length positions))) positions))))
    (when (and window-start (get-buffer-window (current-buffer)))
      (set-window-start (get-buffer-window (current-buffer)) window-start t))))

(defun my/lifeos-schedule--selectable-positions ()
  (let ((position (point-min)) positions)
    (while (< position (point-max))
      (when (get-text-property position 'lifeos-schedule-block)
        (push position positions))
      (setq position (next-single-property-change
                      position 'lifeos-schedule-block nil (point-max))))
    (delete-dups (nreverse positions))))

(defun my/lifeos-schedule--move (forward-p)
  (let ((positions (my/lifeos-schedule--selectable-positions)))
    (unless positions (user-error "Candidate contains no selectable blocks"))
    (goto-char (or (seq-find (if forward-p
                                (lambda (position) (> position (point)))
                              (lambda (position) (< position (point))))
                            (if forward-p positions (reverse positions)))
                   (if forward-p (car positions) (car (last positions)))))))

(defun my/lifeos-schedule-next-block () (interactive) (my/lifeos-schedule--move t))
(defun my/lifeos-schedule-previous-block () (interactive) (my/lifeos-schedule--move nil))

(defun my/lifeos-schedule-block-details ()
  (interactive)
  (let ((block (my/lifeos-schedule--selection)))
    (unless block (user-error "Select a schedule block for details"))
    (with-help-window "*LifeOS Schedule Block*"
      (princ (format "%s\n\nInterval: %s - %s\nSource: %s\nKind: %s\nEstimate: %d minutes\nRationale: %s\n%s"
                     (or (plist-get block :title) "Schedule block")
                     (my/lifeos-schedule--format-minute (plist-get block :start))
                     (my/lifeos-schedule--format-minute (plist-get block :end))
                     (plist-get block :source-id) (plist-get block :kind)
                     (plist-get block :minutes)
                     (or (plist-get block :rationale) "No rationale supplied")
                     (if (eq (plist-get block :kind) 'project-capacity)
                         "This is a coarse project reservation, not a concrete task.\n"
                       "Candidate edits do not modify the source task.\n"))))))

(defun my/lifeos-schedule-visit-source ()
  (interactive)
  (let* ((block (my/lifeos-schedule--selection))
         (marker (plist-get block :marker)))
    (unless block (user-error "Select a schedule block with a source"))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "The selected block has no live snapshot-bound source"))
    (pop-to-buffer (marker-buffer marker))
    (goto-char marker)
    (when (derived-mode-p 'org-mode) (org-show-context))))

(defun my/lifeos-schedule-place-command ()
  (interactive)
  (let* ((block (my/lifeos-schedule--selection))
         (_ (unless block (user-error "Select a candidate task block to place")))
         (date (org-read-date nil nil nil "Exact placement date: "))
         (clock (read-string "Aligned start (HH:MM): ")))
    (unless (string-match-p "\\`[0-2][0-9]:[0-5][0-9]\\'" clock)
      (user-error "Start must use HH:MM"))
    (let* ((start (floor (/ (float-time (my/lifeos--date-time date clock)) 60)))
           (end (+ start (plist-get block :minutes))))
      (unless (zerop (% start 15)) (user-error "Start must align to 15 minutes"))
      (when (yes-or-no-p (format "Place exactly %s through %s? "
                                 (my/lifeos-schedule--format-minute start)
                                 (my/lifeos-schedule--format-minute end)))
        (my/lifeos-schedule-place my/lifeos-schedule-buffer-candidate
                                  (plist-get block :source-id) start)))))

(defun my/lifeos-schedule-exclude-command ()
  (interactive)
  (let ((block (my/lifeos-schedule--selection)))
    (unless block (user-error "Select candidate demand to exclude"))
    (when (yes-or-no-p "Exclude from this candidate? The source task/project remains unchanged. ")
      (my/lifeos-schedule-exclude my/lifeos-schedule-buffer-candidate
                                  (plist-get block :source-id)))))

(defun my/lifeos-schedule-reestimate-command ()
  (interactive)
  (let ((block (my/lifeos-schedule--selection)))
    (unless block (user-error "Select candidate demand to re-estimate"))
    (let ((minutes (read-number
                    (format "Candidate-only estimate (source %dm; Org unchanged): "
                            (or (plist-get block :source-minutes)
                                (plist-get block :minutes))))))
      (my/lifeos-schedule-reestimate my/lifeos-schedule-buffer-candidate
                                     (plist-get block :source-id) minutes))))

(defun my/lifeos-schedule-undo-command ()
  (interactive) (my/lifeos-schedule-undo my/lifeos-schedule-buffer-candidate))

(defun my/lifeos-schedule-discard ()
  (interactive)
  (when (yes-or-no-p "Discard this transient schedule candidate without writing Org? ")
    (my/lifeos-schedule-close my/lifeos-schedule-buffer-candidate)
    (quit-window t)))

(defun my/lifeos-schedule-regenerate ()
  (interactive)
  (let ((candidate my/lifeos-schedule-buffer-candidate))
    (unless (eq (my/lifeos-schedule-candidate-condition candidate) 'stale)
      (user-error "Regeneration is only required for a stale candidate"))
    (let ((history (my/lifeos-schedule-candidate-history candidate)))
      (when (or (null history)
                (yes-or-no-p
                 (format "Regenerate and lose %d candidate edit(s): %s? "
                         (length history)
                         (mapconcat (lambda (edit)
                                      (format "%s %s" (plist-get edit :type)
                                              (plist-get edit :source-id)))
                                    history ", "))))
        (my/lifeos-schedule-close candidate)
        (user-error "Refresh Portfolio Review and press s to create a fresh candidate")))))

(defun my/lifeos-schedule-help ()
  (interactive)
  (with-help-window "*LifeOS Schedule Help*"
    (princ "Schedule candidates and all edits are read-only until complete acceptance.\n\n")
    (princ "n/p navigate; RET details; v source; m exact placement; x exclusion; e candidate-only estimate; u edit undo.\n")
    (princ "r regenerates stale input without replaying edits; a reviews complete replacement; d discards; R restores the latest accepted plan; q only closes the window.\n")
    (princ "Acceptance replaces only the machine-owned future Accepted schedule; tasks, projects, calendars, estimates, deadlines, states, and SCHEDULED values are not changed.\n")))

(defvar my/lifeos-schedule-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (dolist (binding '(("n" . my/lifeos-schedule-next-block)
                       ("p" . my/lifeos-schedule-previous-block)
                       ("RET" . my/lifeos-schedule-block-details)
                       ("v" . my/lifeos-schedule-visit-source)
                       ("m" . my/lifeos-schedule-place-command)
                       ("x" . my/lifeos-schedule-exclude-command)
                       ("e" . my/lifeos-schedule-reestimate-command)
                       ("u" . my/lifeos-schedule-undo-command)
                       ("r" . my/lifeos-schedule-regenerate)
                       ("a" . my/lifeos-schedule-accept-command)
                       ("d" . my/lifeos-schedule-discard)
                       ("R" . my/lifeos-schedule-restore-command)
                       ("h" . my/lifeos-schedule-help)
                       ("q" . quit-window)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map))

(define-derived-mode my/lifeos-schedule-mode special-mode
  "LifeOS-Schedule" "Read-only LifeOS schedule candidate workbench.")

(defun my/lifeos-schedule-show (&optional candidate)
  (interactive)
  (let ((candidate (or candidate my/lifeos-schedule-active-candidate)))
    (unless candidate (user-error "No active LifeOS schedule candidate"))
    (let ((buffer (get-buffer-create "*LifeOS Schedule Candidate*")))
      (with-current-buffer buffer
        (my/lifeos-schedule-mode)
        (setq-local my/lifeos-schedule-buffer-candidate candidate)
        (my/lifeos-schedule-render candidate))
      (pop-to-buffer buffer))))

(defun my/lifeos-schedule--refresh-buffer (candidate)
  (when-let* ((buffer (get-buffer "*LifeOS Schedule Candidate*")))
    (with-current-buffer buffer
      (when (eq my/lifeos-schedule-buffer-candidate candidate)
        (my/lifeos-schedule-render candidate)))))

(defun my/lifeos-schedule--fixed-blocks-from-context (context)
  (let ((request (plist-get context :request)) blocks)
    (dolist (task (append (alist-get 'tasks request) nil) (nreverse blocks))
      (when-let* ((start (alist-get 'fixedStart task))
                  ((numberp start)))
        (let ((minutes (alist-get 'durationMinutes task)))
          (push (list :kind 'fixed :role 'fixed :source-id (alist-get 'id task)
                      :task-id (alist-get 'id task) :start start
                      :end (+ start minutes) :minutes minutes
                      :title (my/lifeos-solver--title context (alist-get 'id task))
                      :marker (gethash (alist-get 'id task)
                                       (plist-get context :source-markers)))
                blocks))))))

(defun my/lifeos-schedule--candidate-blocks-from-portfolio (result context plan)
  (let* ((baseline (alist-get 'baseline result))
         (placements (append (alist-get 'placements baseline) nil))
         (accepted (plist-get plan :blocks))
         blocks)
    (dolist (placement placements)
      (let* ((id (alist-get 'taskId placement))
             (task (seq-find (lambda (item) (equal (alist-get 'id item) id))
                             (append (alist-get 'tasks (plist-get context :request)) nil)))
             (old (seq-find (lambda (item)
                              (equal (plist-get item :source-id)
                                     (if (equal (alist-get 'workType task) "virtual")
                                         (alist-get 'projectId task) id)))
                            accepted))
             (start (alist-get 'start placement))
             (end (alist-get 'end placement))
             (capacity (equal (alist-get 'workType task) "virtual"))
             (source-id (if capacity (alist-get 'projectId task) id))
             (role (cond (capacity 'capacity)
                         ((and old (= start (plist-get old :start))) 'keep)
                         (old 'moved-plan) (t 'new))))
        (push (list :kind (if capacity 'project-capacity 'task) :role role
                    :source-id source-id :task-id (unless capacity id)
                    :project-id (alist-get 'projectId task) :start start :end end
                    :minutes (- end start) :source-minutes (alist-get 'durationMinutes task)
                    :prior-start (and old (not (= start (plist-get old :start)))
                                      (plist-get old :start))
                    :title (my/lifeos-solver--title context source-id)
                    :marker (gethash source-id (plist-get context :source-markers))
                    :rationale (alist-get 'rationale placement))
              blocks)))
    ;; A current-plan seed remains visible when ordinary shadow solving omitted it
    ;; because the accepted interval was occupied context.
    (dolist (old accepted)
      (when (and (>= (plist-get old :start)
                     (alist-get 'start (alist-get 'horizon
                                                  (plist-get context :request))))
                 (not (seq-find (lambda (block)
                                  (equal (plist-get block :source-id)
                                         (plist-get old :source-id)))
                                blocks)))
        (push (append (copy-tree old) (list :role (if (eq (plist-get old :kind) 'task)
                                                       'keep 'capacity)))
              blocks)))
    (nreverse blocks)))

(defun my/lifeos-portfolio-review-open-schedule ()
  "Open one candidate from the exact current Portfolio Review snapshot."
  (interactive)
  (unless (and (boundp 'my/lifeos-portfolio-review-context)
               my/lifeos-portfolio-review-context)
    (user-error "Portfolio Review has no displayed snapshot"))
  (let ((state (my/lifeos-solver--portfolio-evidence-state
                my/lifeos-portfolio-review-result my/lifeos-portfolio-review-context)))
    (unless (equal state "CURRENT")
      (user-error "Portfolio evidence is %s; press r to refresh before opening a candidate"
                  state))
    (if my/lifeos-schedule-active-candidate
        (my/lifeos-schedule-show my/lifeos-schedule-active-candidate)
      (let* ((plan (my/lifeos-schedule-parse-current-plan))
             (context (copy-tree my/lifeos-portfolio-review-context))
             (candidate
              (my/lifeos-schedule-create
               context
               (my/lifeos-schedule--candidate-blocks-from-portfolio
                my/lifeos-portfolio-review-result context plan)
               (my/lifeos-schedule--fixed-blocks-from-context context))))
        (when (timerp my/lifeos-schedule-debounce-timer)
          (cancel-timer my/lifeos-schedule-debounce-timer)
          (setq my/lifeos-schedule-debounce-timer nil))
        (my/lifeos-schedule-apply-response
         candidate
         (my/lifeos-schedule--portfolio-candidate-evidence
          candidate my/lifeos-portfolio-review-result context))
        (my/lifeos-schedule-show candidate)))))

(defun my/lifeos-schedule--replace-subtree (buffer parsed new-text)
  (with-current-buffer buffer
    (org-with-wide-buffer
     (if (plist-get parsed :present-p)
         (pcase-let ((`(,start . ,end) (plist-get parsed :bounds)))
           (goto-char start)
           (delete-region start end)
           (insert new-text))
       (goto-char (point-max))
       (unless (or (= (point-min) (point-max)) (bolp)) (insert "\n"))
       (insert new-text)))))

(defun my/lifeos-schedule-accept (candidate &optional allow-risk)
  "Atomically accept complete CANDIDATE after all freshness checks.
ALLOW-RISK must be non-nil for an `AT RISK' candidate."
  (my/lifeos-schedule--assert-editable candidate)
  (let ((status (my/lifeos-schedule-status candidate)))
    (unless (my/lifeos-schedule-acceptable-p candidate)
      (user-error "%s candidates cannot be accepted"
                  (my/lifeos-schedule--status-text status)))
    (when (and (eq status 'at-risk) (not allow-risk))
      (user-error "AT RISK acceptance requires explicit warning confirmation")))
  (let* ((file (my/lifeos-schedule--planning-file))
         (buffer (find-file-noselect file))
         (parsed (my/lifeos-schedule-parse-current-plan buffer))
         (boundary (my/lifeos-schedule-candidate-horizon-start candidate)))
    (unless (plist-get parsed :valid-p)
      (user-error "Current plan is invalid: %s"
                  (string-join (plist-get parsed :issues) "; ")))
    (when (buffer-modified-p buffer)
      (user-error "planning.org has unsaved changes; save or resolve them first"))
    (unless (verify-visited-file-modtime buffer)
      (user-error "planning.org changed on disk; revert or resolve it first"))
    (unless (equal (my/lifeos-schedule-candidate-input-fingerprint candidate)
                   (my/lifeos-schedule-authoritative-fingerprint))
      (my/lifeos-schedule-mark-stale candidate)
      (user-error "Authoritative planning input changed; regenerate the candidate"))
    (unless (equal (my/lifeos-schedule-candidate-current-plan-fingerprint candidate)
                   (plist-get parsed :fingerprint))
      (my/lifeos-schedule-mark-stale candidate)
      (user-error "Accepted schedule changed; regenerate the candidate"))
    (when (seq-some (lambda (block)
                      (and (< (plist-get block :start) boundary)
                           (< boundary (plist-get block :end))))
                    (plist-get parsed :blocks))
      (user-error "An accepted block now intersects the replacement boundary"))
    (let ((fixed-conflicts
           (my/lifeos-schedule--verify-blocks
            (my/lifeos-schedule-candidate-blocks candidate)
            (my/lifeos-schedule-candidate-fixed-blocks candidate)
            boundary (my/lifeos-schedule-candidate-horizon-end candidate))))
      (when fixed-conflicts
        (user-error "Candidate conflicts at preflight: %s"
                    (string-join fixed-conflicts "; "))))
    (let* ((preserved (seq-filter (lambda (block)
                                    (<= (plist-get block :end) boundary))
                                  (plist-get parsed :blocks)))
           (complete (append preserved
                             (my/lifeos-schedule-candidate-blocks candidate)))
           (accepted-at (floor (/ (float-time) 60)))
           (plan-id (format "plan-%d" accepted-at))
           (new-text (my/lifeos-schedule-serialize-plan
                      plan-id
                      (my/lifeos-schedule-candidate-input-fingerprint candidate)
                      (if preserved
                          (min boundary (apply #'min (mapcar
                                                     (lambda (block)
                                                       (plist-get block :start))
                                                     preserved)))
                        boundary)
                      (my/lifeos-schedule-candidate-horizon-end candidate)
                      accepted-at complete))
           (old-text (plist-get parsed :text))
           (buffer-before
            (with-current-buffer buffer
              (buffer-substring-no-properties (point-min) (point-max))))
           (old-fingerprint (plist-get parsed :fingerprint)))
      (condition-case error-data
          (atomic-change-group
            (my/lifeos-schedule--replace-subtree buffer parsed new-text)
            (with-current-buffer buffer
              (let ((before-save-hook nil) (after-save-hook nil))
                (save-buffer))))
        (error
         (with-current-buffer buffer
           (let ((inhibit-read-only t))
             (erase-buffer)
             (insert buffer-before)
             (set-buffer-modified-p nil)))
         (user-error "Schedule acceptance failed; prior plan retained: %s"
                     (error-message-string error-data))))
      (setq my/lifeos-schedule-restore-token
            (list :file file :prior-text old-text
                  :prior-fingerprint old-fingerprint :result-text new-text
                  :result-fingerprint (my/lifeos-schedule--hash new-text)))
      (my/lifeos-schedule-close candidate)
      (list :accepted-blocks (length complete) :accepted-at accepted-at
            :restore-available t))))

(defun my/lifeos-schedule-accept-command ()
  (interactive)
  (let* ((candidate my/lifeos-schedule-buffer-candidate)
         (status (my/lifeos-schedule-status candidate)))
    (unless (my/lifeos-schedule-acceptable-p candidate)
      (user-error "%s candidates have no acceptance write action"
                  (my/lifeos-schedule--status-text status)))
    (with-help-window "*LifeOS Schedule Acceptance*"
      (princ (format "Complete schedule replacement\n\nStatus: %s (current verified evidence)\nBoundary: %s\nBlocks: %d; exclusions: %d; omissions: %d\n\nThis replaces the complete machine-owned future Accepted schedule in planning.org. Source tasks, projects, calendars, estimates, deadlines, states, and SCHEDULED values will not change.\n"
                     (my/lifeos-schedule--status-text status)
                     (my/lifeos-schedule--format-minute
                      (my/lifeos-schedule-candidate-horizon-start candidate))
                     (length (my/lifeos-schedule-candidate-blocks candidate))
                     (length (my/lifeos-schedule-candidate-exclusions candidate))
                     (length (my/lifeos-schedule-candidate-omissions candidate)))))
    (when (yes-or-no-p "Accept this complete future plan? ")
      (let ((allow-risk
             (or (not (eq status 'at-risk))
                 (yes-or-no-p "AT RISK policies failed. Accept despite these risks? "))))
        (when allow-risk
          (let ((result (my/lifeos-schedule-accept candidate allow-risk)))
            (message "Accepted %d blocks at %s; previous-plan restore is available"
                     (plist-get result :accepted-blocks)
                     (my/lifeos-schedule--format-minute
                      (plist-get result :accepted-at)))))))))

(defun my/lifeos-schedule-restore-available-p ()
  (and my/lifeos-schedule-restore-token
       (let* ((file (plist-get my/lifeos-schedule-restore-token :file))
              (buffer (and (file-readable-p file) (find-file-noselect file)))
              (parsed (and buffer (my/lifeos-schedule-parse-current-plan buffer))))
         (and parsed (plist-get parsed :valid-p)
              (not (buffer-modified-p buffer))
              (equal (plist-get parsed :fingerprint)
                     (plist-get my/lifeos-schedule-restore-token
                                :result-fingerprint))))))

(defun my/lifeos-schedule-restore ()
  "Restore the exact plan preceding the latest acceptance in this session."
  (unless (my/lifeos-schedule-restore-available-p)
    (user-error "Previous-plan restore is unavailable or the accepted plan changed"))
  (let* ((token my/lifeos-schedule-restore-token)
         (buffer (find-file-noselect (plist-get token :file)))
         (parsed (my/lifeos-schedule-parse-current-plan buffer))
         (prior (plist-get token :prior-text)))
    (unless (verify-visited-file-modtime buffer)
      (user-error "planning.org changed on disk; restore refused"))
    (condition-case error-data
        (atomic-change-group
          (with-current-buffer buffer
            (org-with-wide-buffer
             (pcase-let ((`(,start . ,end) (plist-get parsed :bounds)))
               (goto-char start)
               (delete-region start end)
               (when prior (insert prior))))
            (let ((before-save-hook nil) (after-save-hook nil))
              (save-buffer))))
      (error (user-error "Plan restore failed; accepted plan retained: %s"
                         (error-message-string error-data))))
    (setq my/lifeos-schedule-restore-token nil)
    (when my/lifeos-schedule-active-candidate
      (my/lifeos-schedule-mark-stale my/lifeos-schedule-active-candidate))
    t))

(defun my/lifeos-schedule-restore-command ()
  (interactive)
  (unless (my/lifeos-schedule-restore-available-p)
    (user-error "No unchanged previous accepted plan is restorable in this session"))
  (when (yes-or-no-p "Restore the exact plan preceding the latest acceptance? ")
    (my/lifeos-schedule-restore)
    (message "Previous accepted plan restored; refresh planning evidence")))

(provide 'lifeos-schedule)
;;; lifeos-schedule.el ends here
