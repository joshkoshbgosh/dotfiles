;; -*- lexical-binding: t -*-
;;; org/lifeos-forecast.el --- Read-only LifeOS schedule forecasting

(require 'lifeos-planning)
(require 'seq)
(require 'subr-x)

(defconst my/lifeos-forecast-quantum-minutes 15)

(defun my/lifeos--encode-date-time (date clock)
  "Encode local DATE and CLOCK strings."
  (unless (and (string-match-p
                "\\`[0-9]+-[0-9]+-[0-9]+\\'" date)
               (string-match-p "\\`[0-9]+:[0-9]+\\'" clock))
    (error "Invalid date/time: %s %s" date clock))
  (my/lifeos--date-time date clock))

(defun my/lifeos--availability-row (date start end modes)
  "Build an availability window from DATE, START, END, and MODES."
  (list :start (my/lifeos--encode-date-time date start)
        :end (my/lifeos--encode-date-time date end)
        :modes (mapcar #'string-trim (split-string modes "," t))))

(defun my/lifeos--default-planning-marker ()
  "Return the Recurring defaults marker in planning.org."
  (my/lifeos--planning-heading-marker "Recurring defaults"))

(defun my/lifeos--availability-for-week (week-start)
  "Return availability windows for the week beginning WEEK-START."
  (let ((snapshot (my/lifeos--week-marker week-start)) windows)
    (if snapshot
        (dolist (row (cdr (my/lifeos--table-rows-under snapshot "Availability")))
          (when (= (length row) 4)
            (push (my/lifeos--availability-row
                   (nth 0 row) (nth 1 row) (nth 2 row) (nth 3 row))
                  windows)))
      (let* ((defaults (my/lifeos--default-planning-marker))
             (rows (cdr (my/lifeos--table-rows-under defaults "Availability")))
             (week-time (car (my/lifeos--week-times week-start))))
        (dotimes (offset 7)
          (let* ((date (my/lifeos--date-add-days week-start offset))
                 (date-time (my/lifeos--date-time date "00:00"))
                 (day (format-time-string "%A" date-time)))
            (dolist (row rows)
              (when (and (= (length row) 4) (equal (car row) day))
                (push (my/lifeos--availability-row
                       date (nth 1 row) (nth 2 row) (nth 3 row))
                      windows)))))))
    (sort windows (lambda (first second)
                    (time-less-p (plist-get first :start)
                                 (plist-get second :start))))))

(defun my/lifeos--forecast-availability (start-date weeks)
  "Return availability for WEEKS beginning on START-DATE."
  (let (windows)
    (dotimes (offset weeks)
      (setq windows
            (nconc windows
                   (my/lifeos--availability-for-week
                    (my/lifeos--date-add-days start-date (* offset 7))))))
    windows))

(defun my/lifeos--calendar-busy-range-at-point ()
  "Return the current busy calendar event range."
  (when (equal (org-entry-get nil "GCAL_BUSY") "yes")
    (when-let* ((bounds (my/lifeos--entry-section-bounds)))
      (save-excursion
        (goto-char (car bounds))
        (cond
          ((re-search-forward
           "<\\([0-9]+-[0-9]+-[0-9]+\\)[^>\n]*[[:space:]]\\([0-9][0-9]:[0-9][0-9]\\)-\\([0-9][0-9]:[0-9][0-9]\\)>"
           (cdr bounds) t)
          (let ((date (match-string-no-properties 1))
                (start-clock (match-string-no-properties 2))
                (end-clock (match-string-no-properties 3)))
            (let ((start (my/lifeos--encode-date-time date start-clock))
                  (end (my/lifeos--encode-date-time date end-clock)))
              (when (time-less-p end start)
                (setq end (my/lifeos--date-time
                           (my/lifeos--date-add-days date 1) end-clock)))
              (cons start end))))
         ((re-search-forward "<\\([0-9]+-[0-9]+-[0-9]+\\)[^>\n]*>"
                             (cdr bounds) t)
          (let* ((date (match-string-no-properties 1))
                 (start (my/lifeos--encode-date-time date "00:00")))
            (cons start
                  (my/lifeos--date-time
                   (my/lifeos--date-add-days date 1) "00:00")))))))))

(defun my/lifeos--calendar-busy-ranges (start end)
  "Return calendar busy ranges overlapping START and END."
  (let ((file (expand-file-name "calendar.org" org-directory)) ranges)
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-map-entries
          (lambda ()
            (when-let* ((range (my/lifeos--calendar-busy-range-at-point))
                        ((time-less-p (car range) end))
                        ((time-less-p start (cdr range))))
              (push range ranges)))
          nil 'file))))
    (sort ranges (lambda (first second) (time-less-p (car first) (car second))))))

(defun my/lifeos--subtract-busy-range (windows range)
  "Subtract busy RANGE from availability WINDOWS."
  (let ((busy-start (car range))
        (busy-end (cdr range))
        result)
    (dolist (window windows)
      (let ((start (plist-get window :start))
            (end (plist-get window :end)))
        (if (or (not (time-less-p start busy-end))
                (not (time-less-p busy-start end)))
            (push window result)
          (when (time-less-p start busy-start)
            (push (list :start start
                        :end (if (time-less-p busy-start end) busy-start end)
                        :modes (plist-get window :modes))
                  result))
          (when (time-less-p busy-end end)
            (push (list :start (if (time-less-p start busy-end) busy-end start)
                        :end end
                        :modes (plist-get window :modes))
                  result)))))
    (sort result (lambda (first second)
                   (time-less-p (plist-get first :start)
                                (plist-get second :start))))))

(defun my/lifeos--subtract-busy-ranges (windows ranges)
  "Subtract each member of RANGES from WINDOWS."
  (dolist (range ranges windows)
    (setq windows (my/lifeos--subtract-busy-range windows range))))

(defun my/lifeos--quantize-minutes (minutes)
  "Round MINUTES up to the scheduling quantum."
  (* my/lifeos-forecast-quantum-minutes
     (ceiling minutes my/lifeos-forecast-quantum-minutes)))

(defun my/lifeos--record-scheduled-time (record)
  "Return RECORD's scheduled time, if any."
  (or (plist-get record :scheduled)
      (let ((marker (plist-get record :marker)))
        (with-current-buffer (marker-buffer marker)
          (save-excursion
            (goto-char marker)
            (my/lifeos--timed-scheduled-time-at-point))))))

(defun my/lifeos--record-deadline-end (record)
  "Return RECORD's effective deadline at the end of its local day."
  (when-let* ((deadline (plist-get record :deadline)))
    (my/lifeos--end-of-date (my/lifeos--deadline-date deadline))))

(defun my/lifeos--window-contains-p (window start end mode)
  "Return non-nil when WINDOW contains START to END and supports MODE."
  (and (member mode (plist-get window :modes))
       (not (time-less-p start (plist-get window :start)))
       (not (time-less-p (plist-get window :end) end))))

(defun my/lifeos--forecast-slack (record origin)
  "Return RECORD's deadline slack in minutes relative to ORIGIN."
  (if-let* ((deadline (my/lifeos--record-deadline-end record)))
      (- (floor (/ (float-time (time-subtract deadline origin)) 60))
         (or (plist-get record :minutes) 0))
    most-positive-fixnum))

(defun my/lifeos--forecast-priority< (first second critical-ids origin)
  "Return non-nil when FIRST precedes SECOND for CRITICAL-IDS at ORIGIN."
  (let* ((first-slack (my/lifeos--forecast-slack first origin))
         (second-slack (my/lifeos--forecast-slack second origin))
         (first-critical (if (member (plist-get first :id) critical-ids) 0 1))
         (second-critical (if (member (plist-get second :id) critical-ids) 0 1))
         (priority-rank '(("A" . 0) ("B" . 1) ("C" . 2) ("D" . 3)))
         (impact-rank '(("High" . 0) ("Medium" . 1) ("Low" . 2)))
         (first-key (list first-slack first-critical
                          (alist-get (plist-get first :priority) priority-rank 9 nil #'equal)
                          (alist-get (plist-get first :impact) impact-rank 9 nil #'equal)
                          (or (plist-get first :minutes) most-positive-fixnum)
                          (plist-get first :id)))
         (second-key (list second-slack second-critical
                           (alist-get (plist-get second :priority) priority-rank 9 nil #'equal)
                           (alist-get (plist-get second :impact) impact-rank 9 nil #'equal)
                           (or (plist-get second :minutes) most-positive-fixnum)
                           (plist-get second :id))))
    (cond
     ((/= (nth 0 first-key) (nth 0 second-key))
      (< (nth 0 first-key) (nth 0 second-key)))
     ((/= (nth 1 first-key) (nth 1 second-key))
      (< (nth 1 first-key) (nth 1 second-key)))
     ((/= (nth 2 first-key) (nth 2 second-key))
      (< (nth 2 first-key) (nth 2 second-key)))
     ((/= (nth 3 first-key) (nth 3 second-key))
      (< (nth 3 first-key) (nth 3 second-key)))
     ((/= (nth 4 first-key) (nth 4 second-key))
      (< (nth 4 first-key) (nth 4 second-key)))
     (t (string< (nth 5 first-key) (nth 5 second-key))))))

(defun my/lifeos--forecast-order (records edges critical-ids origin)
  "Return a dependency-safe order for RECORDS, EDGES, and CRITICAL-IDS."
  (let ((by-id (make-hash-table :test #'equal))
        (indegree (make-hash-table :test #'equal))
        (dependents (make-hash-table :test #'equal))
        ready order)
    (dolist (record records)
      (let ((id (plist-get record :id)))
        (puthash id record by-id)
        (puthash id (length (alist-get id edges nil nil #'equal)) indegree)))
    (dolist (entry edges)
      (dolist (target (cdr entry))
        (push (car entry) (gethash target dependents))))
    (dolist (record records)
      (when (zerop (gethash (plist-get record :id) indegree))
        (push record ready)))
    (setq ready (sort ready (lambda (first second)
                             (my/lifeos--forecast-priority<
                              first second critical-ids origin))))
    (while ready
      (let* ((record (pop ready))
             (id (plist-get record :id)))
        (push id order)
        (dolist (dependent (gethash id dependents))
          (let ((next (1- (gethash dependent indegree))))
            (puthash dependent next indegree)
            (when (zerop next)
              (push (gethash dependent by-id) ready)
              (setq ready
                     (sort ready (lambda (first second)
                                   (my/lifeos--forecast-priority<
                                    first second critical-ids origin)))))))))
    (nreverse order)))

(defun my/lifeos--latest-time (times fallback)
  "Return the latest non-nil time in TIMES, or FALLBACK."
  (let ((latest fallback))
    (dolist (time times latest)
      (when (and time (time-less-p latest time))
        (setq latest time)))))

(defun my/lifeos--find-forecast-window (windows mode earliest duration deadline)
  "Find a compatible interval in WINDOWS for MODE after EARLIEST."
  (seq-some
   (lambda (window)
     (when (member mode (plist-get window :modes))
       (let* ((window-start (plist-get window :start))
              (start (if (time-less-p window-start earliest)
                         earliest
                       window-start))
              (end (time-add start (seconds-to-time (* duration 60)))))
         (when (and (not (time-less-p (plist-get window :end) end))
                    (or (null deadline) (not (time-less-p deadline end))))
           (cons start end)))))
   windows))

(defun my/lifeos--largest-mode-window (windows mode)
  "Return the largest available MODE window in minutes."
  (let ((largest 0))
    (dolist (window windows largest)
      (when (member mode (plist-get window :modes))
        (setq largest
              (max largest
                   (floor (/ (float-time
                              (time-subtract (plist-get window :end)
                                             (plist-get window :start)))
                             60))))))))

(defun my/lifeos-build-forecast (start-date &optional weeks analysis)
  "Build a read-only forecast beginning START-DATE for WEEKS."
  (let* ((weeks (or weeks 4))
         (horizon-start (car (my/lifeos--week-times start-date)))
         (horizon-end (my/lifeos--date-time
                       (my/lifeos--date-add-days start-date (* weeks 7)) "00:00"))
          (analysis (or analysis (my/lifeos-graph-analysis)))
         (records (plist-get analysis :records))
         (by-id (plist-get analysis :by-id))
         (edges (plist-get analysis :edges))
         (data-errors (my/lifeos--grooming-records 'all))
         (windows (my/lifeos--forecast-availability start-date weeks))
         (calendar-ranges (my/lifeos--calendar-busy-ranges
                           horizon-start horizon-end))
         (windows (my/lifeos--subtract-busy-ranges windows calendar-ranges))
         (critical-ids
          (delete-dups
           (apply #'append
                  (mapcar (lambda (path) (copy-sequence (plist-get path :path)))
                           (or (my/lifeos-critical-paths horizon-start analysis)
                               nil)))))
          (order (and (plist-get analysis :valid-p)
                       (my/lifeos--forecast-order
                        records edges critical-ids horizon-start)))
         (outcomes (make-hash-table :test #'equal))
         (fixed-info (make-hash-table :test #'equal))
         placements failures)
    ;; Reserve fixed commitments before allocating flexible work.
    (dolist (record
             (sort (seq-filter (lambda (item)
                                 (and (member (plist-get item :state)
                                              '("TODO" "NEXT"))
                                      (my/lifeos--record-scheduled-time item)))
                               records)
                   (lambda (first second)
                     (time-less-p (my/lifeos--record-scheduled-time first)
                                  (my/lifeos--record-scheduled-time second)))))
      (let* ((id (plist-get record :id))
             (start (my/lifeos--record-scheduled-time record))
             (minutes (plist-get record :minutes))
             (mode (plist-get record :work-mode))
             (end (and minutes
                       (time-add start
                                 (seconds-to-time
                                  (* (my/lifeos--quantize-minutes minutes) 60)))))
             (deadline (my/lifeos--record-deadline-end record))
             (containing (and end mode
                              (seq-find (lambda (window)
                                          (my/lifeos--window-contains-p
                                           window start end mode))
                                        windows)))
              reason code severity)
        (cond
         ((null mode)
          (setq reason "fixed task has invalid work mode"
                code 'invalid-scheduling-data))
         ((null minutes)
          (if (numberp (plist-get record :balance))
              (setq reason "fixed task needs a new remaining-work estimate"
                    code 'estimate-exhausted severity 'review)
            (setq reason "fixed task has invalid duration"
                  code 'invalid-scheduling-data)))
         ((or (time-less-p start horizon-start)
              (not (time-less-p start horizon-end)))
           (setq reason "fixed start is outside forecast horizon"
                 code 'fixed-outside-horizon))
         ((and deadline (time-less-p deadline end))
           (setq reason "fixed block misses its deadline"
                 code 'fixed-misses-deadline))
         ((null containing)
           (setq reason "fixed block conflicts with availability or calendar"
                 code 'fixed-availability-conflict)))
        (if reason
            (puthash id (list :reason reason :code code
                              :severity (or severity 'conflict))
                     fixed-info)
           (let ((placement (list :id id :title (plist-get record :title)
                                  :start start :end end
                                  :minutes (my/lifeos--quantize-minutes minutes)
                                  :project-id (plist-get record :project-id)
                                 :project-key (plist-get record :project-key)
                                 :mode mode :kind 'fixed)))
            (puthash id placement fixed-info)
            (setq windows (my/lifeos--subtract-busy-range windows (cons start end)))))))
    (if (not (plist-get analysis :valid-p))
        (setq failures
              (list (list :title "Forecast"
                          :code 'invalid-dependency-graph
                          :severity 'error
                          :reason "dependency graph is invalid")))
      (dolist (id order)
        (let* ((record (gethash id by-id))
               (state (plist-get record :state))
               (targets (alist-get id edges nil nil #'equal))
               (failed-dependency
                (seq-find (lambda (target)
                            (plist-get (gethash target outcomes) :reason))
                          targets))
               (dependency-finishes
                (mapcar (lambda (target)
                          (plist-get (gethash target outcomes) :end))
                        targets))
               (earliest (my/lifeos--latest-time dependency-finishes
                                                  horizon-start))
               (fixed (gethash id fixed-info))
               (minutes (plist-get record :minutes))
               (duration (and minutes (my/lifeos--quantize-minutes minutes)))
               (mode (plist-get record :work-mode))
               (deadline (my/lifeos--record-deadline-end record))
                placement reason code severity)
          (cond
           ((equal state "WAITING")
             (setq reason "task is WAITING"
                   code 'waiting-not-scheduled severity 'review))
           (failed-dependency
             (setq reason
                   (format "blocked by unscheduled dependency: %s"
                           (plist-get (gethash failed-dependency by-id) :title))
                   code 'unscheduled-prerequisite severity 'conflict))
            ((null mode)
             (setq reason "invalid work mode"
                   code 'invalid-scheduling-data severity 'error))
            ((null minutes)
             (if (numberp (plist-get record :balance))
                 (setq reason "task needs a new remaining-work estimate"
                       code 'estimate-exhausted severity 'review)
               (setq reason "invalid duration"
                     code 'invalid-scheduling-data severity 'error)))
           (fixed
             (if-let* ((fixed-reason (plist-get fixed :reason)))
                 (setq reason fixed-reason
                       code (plist-get fixed :code)
                       severity (plist-get fixed :severity))
               (if (time-less-p (plist-get fixed :start) earliest)
                   (setq reason "fixed start precedes dependency completion"
                         code 'fixed-before-prerequisite severity 'conflict)
                 (setq placement fixed))))
           (t
            (when-let* ((range (my/lifeos--find-forecast-window
                                windows mode earliest duration deadline)))
              (setq placement
                     (list :id id :title (plist-get record :title)
                            :start (car range) :end (cdr range)
                            :minutes duration
                           :project-id (plist-get record :project-id)
                           :project-key (plist-get record :project-key)
                           :mode mode :kind 'proposed)))
             (unless placement
               (let ((largest (my/lifeos--largest-mode-window windows mode)))
                 (cond
                  ((> duration largest)
                   (setq reason
                         (format "no %s contiguous %s window; largest is %s; split task"
                                 (my/lifeos--format-minutes duration) mode
                                 (my/lifeos--format-minutes largest))
                         code 'no-contiguous-window))
                  ((and deadline (time-less-p deadline horizon-end))
                   (setq reason "no compatible window before deadline"
                         code 'no-window-before-deadline))
                  (t
                   (setq reason "no compatible window in forecast horizon"
                         code 'no-window-in-horizon)))
                 (setq severity 'conflict)))))
          (if placement
              (progn
                (push placement placements)
                (puthash id placement outcomes)
                (unless (eq (plist-get placement :kind) 'fixed)
                  (setq windows
                        (my/lifeos--subtract-busy-range
                         windows
                         (cons (plist-get placement :start)
                               (plist-get placement :end))))))
            (let ((failure (list :id id :title (plist-get record :title)
                                 :project-id (plist-get record :project-id)
                                 :project-key (plist-get record :project-key)
                                 :code code :severity (or severity 'conflict)
                                 :reason reason)))
              (push failure failures)
              (puthash id failure outcomes))))))
    (setq placements
          (mapcar
           (lambda (placement)
             (let* ((offset (max 0 (floor (/ (float-time
                                               (time-subtract
                                                (plist-get placement :start)
                                                horizon-start))
                                              (* 7 24 60 60)))))
                    (week-start (my/lifeos--date-add-days start-date (* offset 7)))
                    (intentions (condition-case nil
                                    (my/lifeos-intentions-for-week week-start)
                                  (error nil)))
                    (record (gethash (plist-get placement :id) by-id)))
               (plist-put placement :intentions
                          (my/lifeos-matching-intentions record intentions))))
           placements))
    (list :start start-date :weeks weeks
          :data-errors data-errors
          :graph analysis
          :placements (sort placements
                            (lambda (first second)
                              (time-less-p (plist-get first :start)
                                           (plist-get second :start))))
          :failures (nreverse failures))))

(defun my/lifeos--forecast-week-rows (forecast)
  "Return weekly intention pressure rows for FORECAST."
  (let ((start (plist-get forecast :start))
        (weeks (plist-get forecast :weeks))
        rows)
    (dotimes (offset weeks (nreverse rows))
       (let ((week-start (my/lifeos--date-add-days start (* offset 7))))
         (dolist (ledger-row
                  (my/lifeos-intention-ledger
                   week-start forecast (plist-get forecast :graph)))
           (push (cons week-start ledger-row) rows))))))

(defun org-dblock-write:lifeos-forecast (params)
  "Write a read-only LifeOS forecast described by PARAMS."
  (let* ((start-date (plist-get params :start))
         (weeks (or (plist-get params :weeks) 4))
         (insertion-point (copy-marker (point)))
         (forecast (and (stringp start-date)
                        (my/lifeos-build-forecast start-date weeks)))
         (analysis (and forecast (plist-get forecast :graph))))
    (unless (stringp start-date)
      (error "lifeos-forecast requires :start YYYY-MM-DD"))
    (goto-char insertion-point)
    (insert (format "Data: %s (%d active headings need grooming)\n\n"
                    (if (plist-get forecast :data-errors) "Incomplete" "Valid")
                    (length (plist-get forecast :data-errors))))
    (insert (format "Graph: %s\n\n"
                    (cond
                     ((plist-get analysis :cycles) "Cycle")
                     ((plist-get analysis :missing-targets) "Missing target")
                     ((plist-get analysis :inactive-targets) "Inactive target")
                     ((plist-get analysis :invalid-targets) "Invalid target")
                     (t "Valid"))))
    (insert "| Kind | Task | Start | End | Intentions | Mode |\n")
    (insert "|------+------+-------+-----+------------+------|\n")
    (dolist (placement (plist-get forecast :placements))
      (insert
       (format "| %s | %s | %s | %s | %s | %s |\n"
               (capitalize (symbol-name (plist-get placement :kind)))
               (plist-get placement :title)
               (format-time-string "%Y-%m-%d %H:%M" (plist-get placement :start))
               (format-time-string "%Y-%m-%d %H:%M" (plist-get placement :end))
                (if-let* ((names (plist-get placement :intentions)))
                    (string-join names ", ") "")
                (plist-get placement :mode))))
    (save-excursion
      (forward-line -1)
      (org-table-align))
    (insert "\nWeekly intention pressure:\n\n")
    (if-let* ((rows (my/lifeos--forecast-week-rows forecast)))
        (progn
          (insert "Rows are independent views; overlapping selectors may credit the same work.\n\n")
          (insert "| Week | Intention | Target | Actual | Fixed | Proposed | To target |\n")
          (insert "|------+-----------+--------+--------+-------+----------+-----------|\n")
          (dolist (row rows)
            (let ((week (car row)) (ledger (cdr row)))
              (insert
               (format "| %s | %s | %s | %s | %s | %s | %s |\n"
                       week (plist-get ledger :name)
                       (if-let* ((v (plist-get ledger :target)))
                           (my/lifeos--format-minutes v) "")
                       (my/lifeos--format-minutes (plist-get ledger :actual))
                       (my/lifeos--format-minutes (plist-get ledger :fixed))
                       (my/lifeos--format-minutes (plist-get ledger :proposed))
                       (if-let* ((v (plist-get ledger :target-remaining)))
                           (my/lifeos--format-minutes v) "")))))
          (save-excursion (forward-line -1) (org-table-align)))
      (insert "No allocation targets are configured.\n"))
    (insert "\nUnscheduled:\n\n")
    (if-let* ((failures (plist-get forecast :failures)))
        (progn
          (insert "| Task | Reason |\n|------+--------|\n")
          (dolist (failure failures)
            (insert (format "| %s | %s |\n"
                            (plist-get failure :title)
                            (plist-get failure :reason))))
          (save-excursion
            (forward-line -1)
            (org-table-align)))
      (insert "None.\n"))
    (set-marker insertion-point nil)))

(provide 'lifeos-forecast)
