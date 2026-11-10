;;; lifeos-solver-test.el --- Tests for LifeOS solver boundary -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(load (expand-file-name "lifeos-planning.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(load (expand-file-name "lifeos-forecast.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(load (expand-file-name "lifeos-schedule.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(load (expand-file-name "lifeos-solver.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(defmacro my/lifeos-solver-test-with-org (content &rest body)
  "Evaluate BODY in a temporary Org buffer containing CONTENT."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (let ((org-todo-keywords
            '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "SOMEDAY(s)"
                        "|" "DONE(d)" "CANCELLED(c)"))))
       (insert ,content)
       (org-mode)
       (goto-char (point-min))
       ,@body)))

(defmacro my/lifeos-solver-test-with-normalization-stubs (&rest body)
  "Evaluate BODY with deterministic external normalization inputs."
  (declare (indent 0) (debug t))
  `(cl-letf (((symbol-function 'my/lifeos--current-week-start)
              (lambda () "2026-10-12"))
             ((symbol-function 'my/lifeos--record-scheduled-time)
              (lambda (record) (plist-get record :scheduled)))
             ((symbol-function 'my/lifeos--record-deadline-end)
              (lambda (record) (plist-get record :deadline-end)))
              ((symbol-function 'my/lifeos--forecast-availability)
               (lambda (&rest _) nil))
              ((symbol-function 'my/lifeos-solver--configuration)
               (lambda (&rest _)
                 (list :values (my/lifeos-solver--configuration-defaults)
                       :source-id "test" :issues nil)))
               ((symbol-function 'my/lifeos-solver--calendar-coverage)
                (lambda (_now horizon-end)
                  (list (my/lifeos-solver--minute horizon-end) nil nil)))
               ((symbol-function 'my/lifeos--grooming-records)
                (lambda (&rest _) nil))
              ((symbol-function 'my/lifeos-solver--calendar-blocks)
               (lambda (&rest _) (cons [] nil)))
              ((symbol-function 'my/lifeos-solver--sleep-blocks)
               (lambda (&rest _) (cons [] nil)))
             ((symbol-function 'my/lifeos-solver--reserve-blocks)
              (lambda (&rest _) (cons [] nil)))
              ((symbol-function 'my/lifeos-solver--intentions)
               (lambda (&rest _) '(:intentions [] :issues nil :assumptions nil))))
     ,@body))

(defun my/lifeos-solver-test-record (id &rest values)
  "Return a valid solver record for ID, overridden by VALUES."
  (append values
          (list :id id :state "TODO" :minutes 60 :work-mode "Deep"
                :priority "A" :impact "High" :eligible t :executable t
                 :diagnostics nil :targets nil :project-id nil)))

(defun my/lifeos-solver-test-solve-result ()
  "Return a structurally valid minimal successful solve result."
  (copy-tree
   '((feasibility . "PROVEN FEASIBLE")
     (safety . "SAFE")
     (resilience . "RESILIENT")
     (placements . nil)
     (reservePlacements . nil)
     (sleepPlacements . nil)
      (intentions . nil)
      (deadlineMargins . nil)
      (conflicts . nil)
     (assumptions . nil)
     (unlockedCommitmentIds . nil)
     (stressResults . nil))))

(defun my/lifeos-solver-test-response (request-id)
  "Return a structurally valid successful response for REQUEST-ID."
  (copy-tree
    `((protocolVersion . "lifeos-planning/v3")
       (solverVersion . "lifeos-z3/0.3.0+z3-solver/5.2.0")
      (requestId . ,request-id)
      (candidateIdentity . nil)
     (status . "ok")
      (baseline . ,(my/lifeos-solver-test-solve-result))
      (scenario . nil)
      (baselinePortfolio
       . ((definitionStatus . "COMPLETE")
          (feasibility . "PROVEN FEASIBLE") (safety . "SAFE")
          (modeledProjectIds . nil) (excludedProjectIds . nil)
          (modeledSubset . nil)
          (globalResult . ,(my/lifeos-solver-test-solve-result))
          (projectResults . nil)))
      (scenarioPortfolio . nil)
      (comparison . nil)
     (negotiationResults . nil)
      (errors . nil))))

(ert-deftest my/lifeos-solver-normalizes-deterministic-virtual-project-work-v3 ()
  (my/lifeos-solver-test-with-normalization-stubs
    (with-temp-buffer
      (let* ((marker (copy-marker (point-min)))
             (project (list :id "project" :key "id:project" :title "Project"
                            :marker marker :deadline "<2026-10-20 Tue>"
                            :commitment 'committed :definition-status 'coarse
                            :project-effort-minutes 300
                            :explicit-effort-minutes 0
                            :explicit-remaining-minutes 0
                            :unallocated-effort-minutes 300
                            :default-work-mode "Deep" :planning-chunk "2:00"
                            :estimate-confidence "Medium" :diagnostics nil))
             (request (my/lifeos-solver-normalize
                       (list :all-records nil :projects (list project)) nil
                       (encode-time 0 0 10 14 10 2026)))
             (repeat (my/lifeos-solver-normalize
                      (list :all-records nil :projects (list project)) nil
                      (encode-time 0 0 10 14 10 2026)))
             (project-json (aref (alist-get 'projects request) 0))
             (tasks (append (alist-get 'tasks request) nil)))
        (should (equal (alist-get 'protocolVersion request) "lifeos-planning/v3"))
        (should (eq (alist-get 'candidate request) :null))
        (should (equal (alist-get 'definitionStatus project-json) "COARSE"))
        (should (equal (mapcar (lambda (task) (alist-get 'id task)) tasks)
                       '("project:virtual:1" "project:virtual:2"
                         "project:virtual:3")))
        (should (equal (mapcar (lambda (task) (alist-get 'durationMinutes task))
                               tasks)
                       '(120 120 60)))
        (should (equal (alist-get 'tasks request) (alist-get 'tasks repeat)))
        (dolist (task tasks)
          (should (equal (alist-get 'projectId task) "project"))
          (should (equal (alist-get 'workType task) "virtual"))
          (should (equal (alist-get 'deadlineSource task) "project"))
          (should (equal (alist-get 'workMode task) "Deep"))
          (should (equal (alist-get 'estimateConfidence
                                    (alist-get 'virtualWork task))
                         "Medium"))
          (should (equal (alist-get 'evidence task)
                         (alist-get 'evidence project-json))))))))

(defun my/lifeos-solver-test-wait-for-process (process)
  "Wait for PROCESS and its sentinel to finish."
  (while (process-live-p process)
    (accept-process-output process 0.05))
  (accept-process-output process 0.05))

(ert-deftest my/lifeos-solver-incomplete-project-empty-properties-normalize-to-null ()
  (let ((project-json
         (my/lifeos-solver--project-json
          '(:id "project" :definition-status incomplete :commitment committed
            :default-work-mode "" :estimate-confidence "" :diagnostics nil))))
    (should (eq (alist-get 'defaultWorkMode project-json) :null))
    (should (eq (alist-get 'estimateConfidence project-json) :null))))

(defun my/lifeos-solver-test-configuration-rows ()
  "Return a complete conservative Solver configuration table."
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
    ("Stress estimate overrun enabled" "yes")
    ("Stress estimate overrun percent" "25")
    ("Stress lose largest Deep window enabled" "yes")
    ("Stress unexpected appointment enabled" "yes")
    ("Stress unexpected appointment duration" "1:00")))

(ert-deftest my/lifeos-solver-configuration-prefers-complete-weekly-table ()
  (let ((weekly-rows (my/lifeos-solver-test-configuration-rows))
        default-read)
    (cl-letf (((symbol-function 'my/lifeos--week-marker) (lambda (_) 'weekly))
              ((symbol-function 'my/lifeos--planning-heading-marker)
               (lambda (_) 'defaults))
              ((symbol-function 'my/lifeos-solver--configuration-table)
               (lambda (marker)
                 (if (eq marker 'weekly) weekly-rows
                   (setq default-read t)))))
      (let* ((result (my/lifeos-solver--configuration "2026-10-12"))
             (values (plist-get result :values)))
        (should-not default-read)
        (should (equal (plist-get result :source-id)
                       "solver-configuration:week:2026-10-12"))
        (should (= (plist-get values :default-safety-buffer) 1440))
        (should (equal (plist-get values :travel-defaults)
                       '(("default" 45 . 45))))
        (should-not (plist-get result :issues))))))

(ert-deftest my/lifeos-solver-configuration-rejects-malformed-whole-table ()
  (let* ((result (my/lifeos-solver--parse-configuration-rows
                  '(("Key" "Value")
                    ("Sleep earliest start" "22:07")
                    ("Sleep earliest start" "22:00")
                    ("Mystery" "1:00"))
                  "test-config"))
         (issues (plist-get result :issues)))
    (should (seq-some (lambda (issue) (string-match-p "aligned" issue)) issues))
    (should (seq-some (lambda (issue) (string-match-p "Duplicate" issue)) issues))
    (should (seq-some (lambda (issue) (string-match-p "Unknown" issue)) issues))
    (should (seq-some (lambda (issue) (string-match-p "Missing" issue)) issues))
    (should (equal (alist-get 'sourceId (plist-get result :evidence))
                   "test-config"))))

(ert-deftest my/lifeos-solver-generates-deterministic-quantized-stress-profiles ()
  (let* ((records (list (my/lifeos-solver-test-record "b" :minutes 31)
                        (my/lifeos-solver-test-record "a" :minutes 60)))
         (availability
          '[((id . "small") (start . 300) (end . 420) (modes . ["Deep"]))
            ((id . "largest") (start . 60) (end . 240) (modes . ["Deep"]))])
         (configuration '(:stress-estimate-enabled t :stress-estimate-percent 25
                          :stress-deep-enabled t :stress-appointment-enabled t
                          :stress-appointment-minutes 60))
         (first (my/lifeos-solver--stress-profiles
                 records availability [] configuration))
         (second (my/lifeos-solver--stress-profiles
                  records availability [] configuration))
         (profiles (append (car first) nil))
         (ids (mapcar (lambda (profile) (alist-get 'id profile)) profiles)))
    (should (equal first second))
    (should (= (length ids) (length (delete-dups (copy-sequence ids)))))
    (should (equal ids '("stress:estimate-overrun"
                         "stress:lose-largest-deep-window"
                         "stress:unexpected-appointment")))
    (dolist (profile profiles)
      (let ((scenario (alist-get 'scenario profile)))
        (dolist (change (append (alist-get 'estimateMultipliers scenario) nil))
          (should (= (alist-get 'percentage change) 25)))
        (dolist (reservation (append (alist-get 'reservations scenario) nil))
          (should (= (% (alist-get 'start reservation) 15) 0))
          (should (= (% (alist-get 'end reservation) 15) 0)))))))

(ert-deftest my/lifeos-solver-calendar-normalizes-attendance-and-travel-evidence ()
  (let* ((directory (make-temp-file "lifeos-calendar-" t))
         (org-directory directory)
         (file (expand-file-name "calendar.org" directory))
         (markers (make-hash-table :test #'equal))
         (configuration '(:travel-defaults (("default" . (45 . 45)))
                          :unknown-travel (60 . 60) :remote-setup 15)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Remote\n:PROPERTIES:\n:ID: remote\n:GCAL_BUSY: yes\n:ATTENDANCE: remote\n:END:\n<2026-10-14 Wed 10:00-11:00>\n"
                    "* Office\n:PROPERTIES:\n:ID: office\n:GCAL_BUSY: yes\n:ATTENDANCE: in-person\n:GCAL_EVENT_TYPE: default\n:TRAVEL_BEFORE: 0:30\n:END:\n<2026-10-14 Wed 13:00-14:00>\n"))
          (let* ((result (my/lifeos-solver--calendar-blocks
                          (encode-time 0 0 0 14 10 2026)
                          (encode-time 0 0 0 15 10 2026)
                          configuration markers))
                 (blocks (append (car result) nil))
                 (kinds (mapcar (lambda (block)
                                  (alist-get 'kind (alist-get 'evidence block)))
                                blocks)))
            (should (= (length blocks) 5))
            (should (member "remote-setup" kinds))
            (should (member "travel-override" kinds))
            (should (member "travel-typed-default" kinds))
            (should (= (hash-table-count markers) 2))
            (should-not (cadr result))))
      (when-let* ((buffer (get-file-buffer file)))
        (set-buffer-modified-p nil)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest my/lifeos-solver-calendar-coverage-requires-fresh-sufficient-evidence ()
  (let* ((now (encode-time 0 0 12 14 10 2026))
         (horizon (encode-time 0 0 12 20 10 2026))
         (my/lifeos-solver-calendar-coverage-max-age-minutes 30))
    (let ((my/org-gcal-last-successful-fetch-time nil)
          (my/org-gcal-calendar-coverage-end nil))
      (should (string-match-p "absent"
                              (car (cadr (my/lifeos-solver--calendar-coverage
                                          now horizon))))))
    (let ((my/org-gcal-last-successful-fetch-time
           (time-subtract now (seconds-to-time 3600)))
          (my/org-gcal-calendar-coverage-end
           (time-add horizon (seconds-to-time 3600))))
      (should (string-match-p "stale"
                              (car (cadr (my/lifeos-solver--calendar-coverage
                                          now horizon))))))
    (let ((my/org-gcal-last-successful-fetch-time now)
          (my/org-gcal-calendar-coverage-end
           (time-subtract horizon (seconds-to-time 60))))
      (should (string-match-p "before"
                              (car (cadr (my/lifeos-solver--calendar-coverage
                                          now horizon))))))))

(ert-deftest my/lifeos-solver-uses-shared-source-aware-selectors ()
  (my/lifeos-solver-test-with-org
      "* Course #project #philosophy\n:PROPERTIES:\n:ID: course-id\n:COURSE: PHIL-101\n:END:\n** TODO Read #task :reading:\n:PROPERTIES:\n:ID: read-id\n:CLIENT: Acme\n:WORK_MODE: Deep\n:END:\n"
    (search-forward "TODO Read")
    (beginning-of-line)
    (let ((record (list :id "read-id" :source-type 'task
                        :project-id "course-id" :work-mode "Deep"
                        :tags '("task" "reading")
                        :project-tags '("project" "philosophy")
                        :properties '(("CLIENT" . "Acme"))
                        :project-properties '(("COURSE" . "PHIL-101"))
                        :marker (copy-marker (point)))))
      (dolist (selector '((tag "reading")
                          (project-tag "philosophy")
                          (project-id "course-id")
                          (prop "CLIENT" "Acme")
                          (project-prop "COURSE" "PHIL-101")
                          (work-mode "Deep")
                          (source task)
                          (and (tag "reading") (work-mode "Deep"))
                          (or (tag "missing") (project-id "course-id"))
                          (not (tag "missing"))))
        (should (my/lifeos-selector-match-p selector record)))
      (should-error
       (my/lifeos-selector-match-p '(progn (delete-file "no")) record)))))

(ert-deftest my/lifeos-solver-rejects-domain-selectors ()
  (cl-letf (((symbol-function 'my/lifeos-intentions-for-week)
             (lambda (_)
               (list (list :id "legacy" :name "Legacy" :minimum nil
                           :target 60 :maximum nil
                           :selector (my/lifeos-read-selector
                                      "(domain \"School\")")
                           :selector-text "(domain \"School\")")))))
    (let ((result (my/lifeos-solver--intentions
                   "2026-10-12" nil nil nil)))
      (should (equal (plist-get result :intentions) []))
      (should (seq-some (lambda (issue)
                          (string-match-p "Unsupported LifeOS selector" issue))
                        (plist-get result :issues))))))

(ert-deftest my/lifeos-solver-no-intentions-discloses-without-targets ()
  (cl-letf (((symbol-function 'my/lifeos-intentions-for-week) (lambda (_) nil)))
    (let ((result (my/lifeos-solver--intentions
                   "2026-10-12" nil nil nil)))
      (should (equal (plist-get result :intentions) []))
      (should-not (plist-get result :issues))
      (should (equal (plist-get result :assumptions)
                     '("No allocation targets are configured."))))))

(ert-deftest my/lifeos-solver-canonicalizes-overlapping-availability ()
  (let* ((minute (lambda (value) (seconds-to-time (* value 60))))
         (windows (list (list :start (funcall minute 0) :end (funcall minute 120)
                              :modes '("Deep"))
                        (list :start (funcall minute 60) :end (funcall minute 180)
                              :modes '("Shallow"))))
         (result (append (my/lifeos-solver--canonical-availability windows) nil)))
    (should (= (length result) 3))
    (should (equal (alist-get 'modes (nth 0 result)) ["Deep"]))
    (should (equal (alist-get 'modes (nth 1 result)) ["Deep" "Shallow"]))
    (should (equal (alist-get 'modes (nth 2 result)) ["Shallow"]))))

(ert-deftest my/lifeos-solver-normalization-preserves-unknown-duration ()
  (let* ((record '(:id "task" :state "TODO" :minutes nil :work-mode "Deep"
                   :priority "A" :impact "High" :deadline "<2026-12-31 Thu>"
                   :project-id nil :targets nil :eligible t :executable t))
         (analysis (list :all-records (list record) :projects nil)))
    (cl-letf (((symbol-function 'my/lifeos--record-scheduled-time) (lambda (_) nil))
               ((symbol-function 'my/lifeos--forecast-availability) (lambda (&rest _) nil))
               ((symbol-function 'my/lifeos-solver--configuration)
                (lambda (&rest _)
                  (list :values (my/lifeos-solver--configuration-defaults)
                        :source-id "test" :issues nil)))
               ((symbol-function 'my/lifeos-solver--calendar-coverage)
                (lambda (_now horizon-end)
                  (list (my/lifeos-solver--minute horizon-end) nil nil)))
               ((symbol-function 'my/lifeos-solver--calendar-blocks)
                (lambda (&rest _) (cons [] nil)))
               ((symbol-function 'my/lifeos--grooming-records) (lambda (&rest _) nil))
               ((symbol-function 'my/lifeos-solver--sleep-blocks)
                (lambda (&rest _) (cons [] nil)))
              ((symbol-function 'my/lifeos-solver--reserve-blocks)
               (lambda (&rest _) (cons [] nil)))
               ((symbol-function 'my/lifeos-solver--intentions)
                (lambda (&rest _) '(:intentions [] :issues nil :assumptions nil))))
      (let* ((request (my/lifeos-solver-normalize analysis))
             (task (aref (alist-get 'tasks request) 0)))
        (should (eq (alist-get 'durationMinutes task) :null))
        (should (>= (alist-get 'end (alist-get 'horizon request))
                    (alist-get 'deadline task)))
        (should (stringp (json-serialize request)))))))

(ert-deftest my/lifeos-solver-stale-response-is-rejected ()
  (let ((my/lifeos-solver-current-request-id "new")
        (new (my/lifeos-solver-test-response "new")))
    (should-not
     (my/lifeos-solver--current-response-p
      (cons '(requestId . "old") (cdr new)) "old"))
    (should
     (my/lifeos-solver--current-response-p new "new"))))

(ert-deftest my/lifeos-solver-shadow-failure-does-not-break-heuristic-refresh ()
  (let ((my/lifeos-project-analysis-cache nil)
        (my/lifeos-project-analysis-stale t)
        (my/lifeos-solver-last-error nil))
    (cl-letf (((symbol-function 'my/lifeos-graph-analysis)
               (lambda () '(:projects nil :all-records nil)))
              ((symbol-function 'my/lifeos-build-forecast)
               (lambda (&rest _) '(:placements nil :failures nil)))
              ((symbol-function 'my/lifeos--project-summaries)
               (lambda (&rest _) (make-hash-table :test #'equal)))
              ((symbol-function 'my/lifeos--forecast-task-diagnostics)
               (lambda (_) (make-hash-table :test #'equal)))
              ((symbol-function 'my/lifeos-solver-request-shadow)
               (lambda (&rest _) (error "shadow unavailable"))))
      (should (my/lifeos-refresh-project-analysis))
      (should-not my/lifeos-project-analysis-stale)
      (should (equal my/lifeos-solver-last-error "shadow unavailable")))))

(ert-deftest my/lifeos-solver-intentions-carry-week-window-and-match-evidence ()
  (let ((record '(:id "read" :source-type task :work-mode "Deep")))
    (cl-letf (((symbol-function 'my/lifeos-intentions-for-week)
               (lambda (_)
                 (list (list :id "reading" :name "Reading" :minimum 60
                             :target 120 :maximum nil
                             :selector '(work-mode "Deep")
                             :selector-text "(work-mode \"Deep\")"))))
              ((symbol-function 'my/lifeos--week-times)
               (lambda (_) (list (seconds-to-time 0) (seconds-to-time (* 7 86400)))))
              ((symbol-function 'my/lifeos-solver--direct-clocked-minutes-in-range)
               (lambda (&rest _) 30))
              ((symbol-function 'my/lifeos-solver--calendar-selector-allocation)
               (lambda (&rest _) '(0))))
      (let* ((result (my/lifeos-solver--intentions
                      "2026-10-12" (list record) nil))
              (intentions (plist-get result :intentions))
              (intention (aref intentions 0)))
        (should (= (alist-get 'actualMinutes intention) 30))
        (should (= (alist-get 'windowStart intention) 0))
        (should (= (alist-get 'windowEnd intention) (* 7 24 60)))
        (should (equal (alist-get 'matchedTaskIds intention) ["read"]))
        (should (= (length (alist-get 'matchEvidence intention)) 1))))))

(ert-deftest my/lifeos-solver-selector-evaluation-does-not-mutate-org ()
  (my/lifeos-solver-test-with-org
      "* TODO Read #task :reading:\n:PROPERTIES:\n:ID: read-id\n:WORK_MODE: Deep\n:END:\n"
    (set-buffer-modified-p nil)
    (let ((record (list :id "read-id" :source-type 'task
                        :tags '("task" "reading") :work-mode "Deep"
                        :marker (copy-marker (point)))))
      (should (my/lifeos-selector-match-p '(tag "reading") record))
      (should-not (buffer-modified-p)))))

(ert-deftest my/lifeos-solver-virtual-chunks-match-owning-project-evidence ()
  (let* ((project '(:id "course" :default-work-mode "Deep"
                    :definition-status coarse :unallocated-effort-minutes 120
                    :planning-chunk "1:00" :tags ("school")
                    :properties (("CLIENT" . "University"))))
         (intentions
          (list (list :id "school" :name "School" :minimum nil :target 180
                      :maximum nil
                      :selector '(and (project-tag "school")
                                      (project-prop "CLIENT" "University"))
                      :selector-text
                      "(and (project-tag \"school\") (project-prop \"CLIENT\" \"University\"))"))))
    (cl-letf (((symbol-function 'my/lifeos-intentions-for-week)
               (lambda (_) intentions))
              ((symbol-function 'my/lifeos--week-times)
               (lambda (_) (list (seconds-to-time 0)
                                  (seconds-to-time (* 7 86400)))))
              ((symbol-function 'my/lifeos-solver--calendar-selector-allocation)
               (lambda (&rest _) '(0))))
      (let* ((result (my/lifeos-solver--intentions
                      "2026-10-12" nil (list project)))
             (intention (aref (plist-get result :intentions) 0)))
        (should (equal (alist-get 'matchedTaskIds intention)
                       ["course:virtual:1" "course:virtual:2"]))))))

(ert-deftest my/lifeos-solver-recursive-calendar-selectors-credit-only-timed-events ()
  (let* ((directory (make-temp-file "lifeos-intention-calendar-" t))
         (org-directory directory)
         (file (expand-file-name "calendar.org" directory))
         (selector '(or (project-tag "school") (calendar-role "school"))))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Timed\n:PROPERTIES:\n:ID: timed\n:CALENDAR_ROLE: school\n:END:\n<2026-10-14 Wed 10:00-11:30>\n"
                    "* Roleless timed\n:PROPERTIES:\n:ID: roleless\n:END:\n<2026-10-14 Wed 14:00-15:00>\n"
                    "* All day\n:PROPERTIES:\n:ID: all-day\n:CALENDAR_ROLE: school\n:END:\n<2026-10-15 Thu>\n"))
          (let* ((start (encode-time 0 0 0 12 10 2026))
                 (end (encode-time 0 0 0 19 10 2026))
                 (allocation (my/lifeos-solver--calendar-selector-allocation
                              selector start end))
                 (roleless (my/lifeos-solver--calendar-selector-allocation
                            '(not (calendar-role "school")) start end)))
            (should (= (car allocation) 90))
            (should (= (length (cdr allocation)) 1))
            (should (= (car roleless) 60))
            (should (= (length (cdr roleless)) 1))))
      (when-let* ((buffer (get-file-buffer file)))
        (set-buffer-modified-p nil)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest my/lifeos-solver-horizon-starts-at-injected-next-quantum ()
  (my/lifeos-solver-test-with-normalization-stubs
    (let* ((now (encode-time 1 7 10 14 10 2026))
           (request (my/lifeos-solver-normalize
                     (list :all-records nil :projects nil) nil now))
           (start (alist-get 'start (alist-get 'horizon request)))
           (now-minute (/ (float-time now) 60.0)))
      (should (= (% start 15) 0))
      (should (>= start now-minute))
      (should (< (- start now-minute) 15)))))

(ert-deftest my/lifeos-solver-normalizes-candidates-and-active-prerequisites ()
  (my/lifeos-solver-test-with-normalization-stubs
    (let* ((active (my/lifeos-solver-test-record "active"))
           (done (my/lifeos-solver-test-record "done" :state "DONE"))
           (waiting (my/lifeos-solver-test-record "waiting" :state "WAITING"))
           (invalid
             (my/lifeos-solver-test-record
              "invalid" :eligible nil
              :diagnostics (list (my/lifeos--diagnostic
                                  'invalid-impact 'error "No impact"))))
           (root (my/lifeos-solver-test-record
                  "root" :deadline "<2026-10-20 Tue>"
                  :deadline-end (encode-time 0 0 0 21 10 2026)
                  :targets '("active" "done")))
           (request (my/lifeos-solver-normalize
                     (list :all-records
                            (list active done waiting invalid root)
                           :projects nil)
                     nil (encode-time 0 0 10 14 10 2026)))
           (tasks (append (alist-get 'tasks request) nil))
           (ids (mapcar (lambda (task) (alist-get 'id task)) tasks))
           (root-json (seq-find (lambda (task)
                                  (equal (alist-get 'id task) "root"))
                                tasks)))
      (should (equal ids '("active" "root")))
      (should (equal (alist-get 'prerequisiteIds root-json) ["active"]))
      (should (seq-some (lambda (assumption)
                          (string-match-p "WAITING" assumption))
                        (alist-get 'inputAssumptions request)))
      (should (seq-some (lambda (assumption)
                           (string-match-p "Completed or cancelled" assumption))
                         (alist-get 'inputAssumptions request)))
      (should-not (seq-some (lambda (assumption)
                              (string-match-p "DOMAIN" assumption))
                            (alist-get 'inputAssumptions request))))))

(ert-deftest my/lifeos-solver-invalid-work-only-blocks-mandatory-closure ()
  (my/lifeos-solver-test-with-normalization-stubs
    (let* ((diagnostic (list (my/lifeos--diagnostic
                              'invalid-impact 'error "Bad impact")))
           (optional (my/lifeos-solver-test-record
                      "optional" :diagnostics diagnostic :eligible nil))
           (required (my/lifeos-solver-test-record
                      "required" :diagnostics diagnostic :eligible nil))
           (root (my/lifeos-solver-test-record
                  "root" :deadline "<2026-10-20 Tue>"
                  :deadline-end (encode-time 0 0 0 21 10 2026)
                  :targets '("required")))
           (request (my/lifeos-solver-normalize
                     (list :all-records (list optional required root)
                           :projects nil
                           :invalid-targets '(("root" . "required")))
                     nil (encode-time 0 0 10 14 10 2026)))
           (hard (append (alist-get 'hardIssues request) nil))
           (assumptions (append (alist-get 'inputAssumptions request) nil)))
      (should (seq-some (lambda (issue) (string-match-p "required" issue)) hard))
      (should-not (seq-some (lambda (issue) (string-match-p "optional" issue)) hard))
      (should (seq-some (lambda (text) (string-match-p "invalid optional" text))
                        assumptions)))))

(ert-deftest my/lifeos-solver-reserve-partition-never-creates-small-tail ()
  (let* ((blocks (my/lifeos-solver--reserve-chunks
                  "reserve" (seconds-to-time 0) (seconds-to-time 86400)
                  105 45))
         (sizes (mapcar (lambda (block) (alist-get 'minimumMinutes block)) blocks)))
    (should (equal sizes '(60 45)))
    (should (seq-every-p (lambda (size) (>= size 45)) sizes))))

(ert-deftest my/lifeos-solver-reserve-policy-handles-zero-impossible-and-usable-days ()
  (let* ((start (encode-time 0 0 0 14 10 2026))
         (end (encode-time 0 0 0 16 10 2026))
         (day-two-start (my/lifeos-solver--minute
                         (encode-time 0 0 9 15 10 2026)))
         (day-two-end (my/lifeos-solver--minute
                       (encode-time 0 0 17 15 10 2026)))
         (availability `[((start . ,day-two-start) (end . ,day-two-end))]))
    (let ((my/lifeos-solver-daily-reserve-minutes 60)
          (my/lifeos-solver-weekly-reserve-minutes 0)
          (my/lifeos-solver-reserve-block-minutes 30))
      (let* ((result (my/lifeos-solver--reserve-blocks start end availability))
             (ids (mapcar (lambda (block) (alist-get 'id block))
                          (append (car result) nil))))
        (should (= (length ids) 2))
        (should (seq-every-p (lambda (id) (string-match-p "2026-10-15" id)) ids))
        (should-not (cdr result))))
    (let ((my/lifeos-solver-daily-reserve-minutes 30)
          (my/lifeos-solver-weekly-reserve-minutes 0)
          (my/lifeos-solver-reserve-block-minutes 45))
      (let ((result (my/lifeos-solver--reserve-blocks start end availability)))
        (should (equal (car result) []))
        (should (seq-some (lambda (issue) (string-match-p "smaller" issue))
                          (cdr result)))))))

(ert-deftest my/lifeos-solver-zero-configuration-is-not-unconfigured ()
  (my/lifeos-solver-test-with-normalization-stubs
    (let ((my/lifeos-solver-default-safety-buffer-minutes 0)
          (my/lifeos-solver-daily-reserve-minutes 0)
          (my/lifeos-solver-weekly-reserve-minutes 0)
          (my/lifeos-solver-reserve-block-minutes 0))
      (let ((request (my/lifeos-solver-normalize
                      (list :all-records nil :projects nil)
                      nil (encode-time 0 0 10 14 10 2026))))
        (should-not
         (seq-some (lambda (issue) (string-match-p "not.*configured" issue))
                   (alist-get 'safetyIssues request)))))))

(ert-deftest my/lifeos-solver-validates-response-envelope ()
  (let ((response (my/lifeos-solver-test-response "request")))
    (should-not (my/lifeos-solver--response-validation-error response "request"))
    (let ((missing (assq-delete-all 'candidateIdentity (copy-tree response))))
      (should (string-match-p
               "candidate identity"
               (my/lifeos-solver--response-validation-error missing "request"))))
    (let ((candidate (copy-tree response)))
      (setf (alist-get 'candidateIdentity candidate)
            '((candidateId . "candidate") (revision . 1)
              (capturedInputFingerprint . "fingerprint")
              (normalizedRequestId . "request")))
      (should (string-match-p
               "candidate identity"
               (my/lifeos-solver--response-validation-error candidate "request"))))
    (setf (alist-get 'protocolVersion response) "wrong")
    (should (string-match-p
             "protocol version"
              (my/lifeos-solver--response-validation-error response "request")))))

(ert-deftest my/lifeos-solver-validates-v3-project-attribution-and-portfolios ()
  (let ((response (my/lifeos-solver-test-response "request")))
    (setf (alist-get 'conflicts (alist-get 'baseline response))
          '(((constraintId . "constraint") (sourceId . "source")
             (kind . "task-overlap") (message . "Projects conflict")
             (taskIds . ("task-a" "task-b"))
             (projectIds . ("project-a" "project-b")) (shared . nil))))
    (should-not (my/lifeos-solver--response-validation-error response "request"))
    (setf (alist-get 'projectIds
                     (car (alist-get 'conflicts (alist-get 'baseline response))))
          '("project-a" 7))
    (should (string-match-p
             "malformed conflicts"
             (my/lifeos-solver--response-validation-error response "request")))
    (setq response (my/lifeos-solver-test-response "request"))
    (setf (alist-get 'baselinePortfolio response) '((definitionStatus . "COMPLETE")))
    (should (string-match-p
             "Baseline portfolio"
             (my/lifeos-solver--response-validation-error response "request")))
    (setq response (my/lifeos-solver-test-response "request"))
    (setf (alist-get 'comparison response) '((interpretation . "missing deltas")))
    (should (string-match-p
             "comparison"
             (my/lifeos-solver--response-validation-error response "request")))))

(ert-deftest my/lifeos-solver-timeout-scales-with-stages-and-queries ()
  (let ((request '((timeoutMs . 1000)
                    (schedulingQuantumMinutes . 15)
                    (stressProfiles . [a b])
                    (scenario . ((id . "scenario")))
                    (negotiationQueries
                     . [((kind . "maximum-safe-discretionary-duration")
                         (start . 120) (maximumEnd . 240))
                        ((kind . "minimum-required-work-in-window"))]))))
    (should (= (my/lifeos-solver--request-stage-count request) 18))
    (should (= (my/lifeos-solver--process-timeout-seconds request) 20.0))))

(ert-deftest my/lifeos-solver-stale-process-cannot-cancel-current-timer ()
  (let* ((old-process (make-pipe-process :name "lifeos-old-test" :noquery t))
         (new-process (make-pipe-process :name "lifeos-new-test" :noquery t))
         (old-timer (run-at-time 60 nil #'ignore))
         (new-timer (run-at-time 60 nil #'ignore))
         (my/lifeos-solver-process-timer new-timer))
    (unwind-protect
        (progn
          (process-put old-process 'lifeos-timer old-timer)
          (process-put new-process 'lifeos-timer new-timer)
          (my/lifeos-solver--cancel-process-timer old-process)
          (should (eq my/lifeos-solver-process-timer new-timer))
          (should (memq new-timer timer-list)))
      (cancel-timer old-timer)
      (cancel-timer new-timer)
      (delete-process old-process)
      (delete-process new-process))))

(ert-deftest my/lifeos-solver-parses-structured-nonzero-response-and-stderr ()
  (my/lifeos-solver-test-with-normalization-stubs
    (let* ((my/lifeos-solver-request-sequence 0)
           (my/lifeos-solver-current-request-id nil)
           (my/lifeos-solver-process nil)
            (my/lifeos-solver-process-timer nil)
            (my/lifeos-solver-last-error nil)
            rerendered
            (my/lifeos-solver-command
            '("sh" "-c"
              "sleep 0.05; printf '%s\n' '{\"protocolVersion\":\"lifeos-planning/v3\",\"solverVersion\":\"lifeos-z3/0.3.0+z3-solver/5.2.0\",\"requestId\":\"emacs-1\",\"candidateIdentity\":null,\"status\":\"invalid-request\",\"baseline\":null,\"scenario\":null,\"baselinePortfolio\":null,\"scenarioPortfolio\":null,\"comparison\":null,\"negotiationResults\":[],\"errors\":[{\"path\":\"tasks.0\",\"message\":\"bad task\"}]}' ; printf '%s\n' 'diagnostic output' >&2; exit 2")))
      (cl-letf (((symbol-function 'my/lifeos-solver--refresh-report-buffer)
                 (lambda () (setq rerendered t))))
        (my/lifeos-solver-request-shadow
         (list :all-records nil :projects nil))
        (let ((process my/lifeos-solver-process))
          (my/lifeos-solver-test-wait-for-process process)))
      (should rerendered)
      (should (string-match-p "invalid-request" my/lifeos-solver-last-error))
      (should (string-match-p "tasks.0: bad task" my/lifeos-solver-last-error))
      (should (string-match-p "stderr: diagnostic output"
                               my/lifeos-solver-last-error)))))

(ert-deftest my/lifeos-solver-malformed-success-cannot-replace-last-good ()
  (my/lifeos-solver-test-with-normalization-stubs
    (let* ((previous (my/lifeos-solver-test-response "previous"))
           (my/lifeos-solver-last-good-result previous)
           (my/lifeos-solver-request-sequence 0)
           (my/lifeos-solver-current-request-id nil)
           (my/lifeos-solver-process nil)
           (my/lifeos-solver-process-timer nil)
           (my/lifeos-solver-last-error nil)
           (my/lifeos-solver-command
            '("sh" "-c"
              "printf '%s\n' '{\"protocolVersion\":\"lifeos-planning/v3\",\"solverVersion\":\"lifeos-z3/0.3.0+z3-solver/5.2.0\",\"requestId\":\"emacs-1\",\"candidateIdentity\":null,\"status\":\"ok\",\"baseline\":{},\"scenario\":null,\"baselinePortfolio\":null,\"scenarioPortfolio\":null,\"comparison\":null,\"negotiationResults\":[],\"errors\":[]}'")))
      (my/lifeos-solver-request-shadow (list :all-records nil :projects nil))
      (my/lifeos-solver-test-wait-for-process my/lifeos-solver-process)
      (should (eq my/lifeos-solver-last-good-result previous))
      (should (string-match-p "Baseline result"
                              my/lifeos-solver-last-error)))))

(ert-deftest my/lifeos-solver-publishes-request-markers-only-on-success ()
  (my/lifeos-solver-test-with-normalization-stubs
    (with-temp-buffer
      (let* ((record (my/lifeos-solver-test-record
                      "task" :marker (copy-marker (point))))
             (old-markers (make-hash-table :test #'equal))
             (my/lifeos-solver-source-markers old-markers)
             (my/lifeos-solver-request-sequence 0)
             (my/lifeos-solver-current-request-id nil)
             (my/lifeos-solver-process nil)
             (my/lifeos-solver-process-timer nil)
             (my/lifeos-solver-last-request-context nil)
              (my/lifeos-solver-command
               '("sh" "-c"
                  "sleep 0.05; printf '%s\n' '{\"protocolVersion\":\"lifeos-planning/v3\",\"solverVersion\":\"lifeos-z3/0.3.0+z3-solver/5.2.0\",\"requestId\":\"emacs-1\",\"candidateIdentity\":null,\"status\":\"ok\",\"baseline\":{\"feasibility\":\"PROVEN FEASIBLE\",\"safety\":\"SAFE\",\"resilience\":\"RESILIENT\",\"placements\":[],\"reservePlacements\":[],\"sleepPlacements\":[],\"intentions\":[],\"deadlineMargins\":[],\"conflicts\":[],\"assumptions\":[],\"unlockedCommitmentIds\":[],\"stressResults\":[]},\"scenario\":null,\"baselinePortfolio\":{\"definitionStatus\":\"COMPLETE\",\"feasibility\":\"PROVEN FEASIBLE\",\"safety\":\"SAFE\",\"modeledProjectIds\":[],\"excludedProjectIds\":[],\"modeledSubset\":false,\"globalResult\":{\"feasibility\":\"PROVEN FEASIBLE\",\"safety\":\"SAFE\",\"resilience\":\"RESILIENT\",\"placements\":[],\"reservePlacements\":[],\"sleepPlacements\":[],\"intentions\":[],\"deadlineMargins\":[],\"conflicts\":[],\"assumptions\":[],\"unlockedCommitmentIds\":[],\"stressResults\":[]},\"projectResults\":[]},\"scenarioPortfolio\":null,\"comparison\":null,\"negotiationResults\":[],\"errors\":[]}'")))
        (puthash "old" (copy-marker (point)) old-markers)
        (my/lifeos-solver-request-shadow
         (list :all-records (list record) :projects nil))
        (should (eq my/lifeos-solver-source-markers old-markers))
        (should (gethash "old" my/lifeos-solver-source-markers))
        (let ((process my/lifeos-solver-process))
          (my/lifeos-solver-test-wait-for-process process))
        (should-not (eq my/lifeos-solver-source-markers old-markers))
        (should (gethash "task" my/lifeos-solver-source-markers))
         (should (equal (plist-get my/lifeos-solver-last-request-context
                                   :request-id)
                        "emacs-1"))))))

(defun my/lifeos-solver-test-request ()
  "Return a minimal normalized request for builder tests."
  '((requestId . "test")
    (horizon . ((start . 100) (end . 1000)))
    (schedulingQuantumMinutes . 15)
    (tasks . [((id . "task") (fixedStart . :null))
              ((id . "fixed") (fixedStart . 200))])
    (busy . [((id . "busy"))])
    (intentions . [((id . "intention"))])
    (scenario . :null)
    (negotiationQueries . [])))

(ert-deftest my/lifeos-solver-normalize-serializes-negotiation-queries ()
  (my/lifeos-solver-test-with-normalization-stubs
    (let* ((query '((id . "q")
                    (kind . "maximum-safe-discretionary-duration")
                    (scope . "baseline") (start . 100) (maximumEnd . 200)))
           (request (my/lifeos-solver-normalize
                     (list :all-records nil :projects nil) nil
                     (encode-time 0 0 10 14 10 2026) nil (list query))))
      (should (equal (alist-get 'negotiationQueries request) (vector query)))
      (should (string-match-p "negotiationQueries" (json-serialize request))))))

(ert-deftest my/lifeos-solver-snapshot-pairs-current-analysis-forecast-and-query-free-request ()
  (my/lifeos-solver-test-with-normalization-stubs
    (let* ((analysis (list :all-records nil :projects nil))
           (forecast (list :placements nil :failures nil))
           (my/lifeos-project-analysis-cache
            (list :analysis analysis :forecast forecast))
           (context (my/lifeos-solver--snapshot)))
      (should (eq (plist-get context :analysis) analysis))
      (should (eq (plist-get context :forecast) forecast))
      (should (equal (alist-get 'negotiationQueries
                                (plist-get context :request)) [])))))

(ert-deftest my/lifeos-solver-scenario-builders-are-structured-and-composable ()
  (let* ((request (my/lifeos-solver-test-request))
         (scenario (my/lifeos-solver-scenario-reserve request 120 180 "new-busy"))
         (scenario (my/lifeos-solver-scenario-estimate-change
                    request "task" 90 scenario))
         (scenario (my/lifeos-solver-scenario-intention-bounds
                    request "intention" 30 60 120 scenario))
         (scenario (my/lifeos-solver-scenario-unlock request "fixed" scenario)))
    (should (equal (alist-get 'kind (aref (alist-get 'reservations scenario) 0))
                   "scenario-reservation"))
    (should (= (alist-get 'durationMinutes
                          (aref (alist-get 'estimateChanges scenario) 0)) 90))
    (should (= (alist-get 'targetMinutes
                          (aref (alist-get 'intentionChanges scenario) 0)) 60))
    (should (equal (alist-get 'unlockedCommitmentIds scenario) ["fixed"]))
    (should-error (my/lifeos-solver-scenario-reserve request 120 179)
                  :type 'user-error)
    (should-error (my/lifeos-solver-scenario-unlock request "task")
                  :type 'user-error)))

(ert-deftest my/lifeos-solver-project-scenario-changes-compose-read-only ()
  (let* ((request (my/lifeos-solver-test-request))
         (_ (setf (alist-get 'projects request)
                  '[((id . "project") (projectEffortMinutes . 120))]))
         (scenario (my/lifeos-solver-scenario-project-change
                    request "project" '((projectEffortMinutes . 180))))
         (scenario (my/lifeos-solver-scenario-project-change
                    request "project"
                    '((deadline . 900) (commitment . "UNCOMMITTED")
                      (defaultWorkMode . "Shallow")
                      (planningChunkMinutes . 45)
                      (estimateConfidence . "High"))
                    scenario))
         (change (aref (alist-get 'projectChanges scenario) 0)))
    (should (= (length (alist-get 'projectChanges scenario)) 1))
    (should (= (alist-get 'projectEffortMinutes change) 180))
    (should (= (alist-get 'deadline change) 900))
    (should (equal (alist-get 'commitment change) "UNCOMMITTED"))
    (should (equal (alist-get 'defaultWorkMode change) "Shallow"))
    (should (= (alist-get 'planningChunkMinutes change) 45))
    (should (equal (alist-get 'estimateConfidence change) "High"))))

(ert-deftest my/lifeos-solver-builds-all-five-project-query-kinds ()
  (let ((request (my/lifeos-solver-test-request)))
    (setf (alist-get 'projects request) '[((id . "project"))])
    (let ((queries
           (list
            (my/lifeos-solver-negotiation-query
             request "maximum-project-effort" "a" "baseline"
             :project-id "project" :maximum-effort-minutes 240 :assurance "safe")
            (my/lifeos-solver-negotiation-query
             request "minimum-project-work-in-window" "b" "baseline"
             :project-id "project" :start 120 :end 300 :assurance "deadline-only")
            (my/lifeos-solver-negotiation-query
             request "latest-safe-project-start" "c" "baseline"
             :project-id "project" :earliest-start 120 :latest-start 300)
            (my/lifeos-solver-negotiation-query
             request "earliest-feasible-project-deadline" "d" "baseline"
             :project-id "project" :earliest-deadline 120 :latest-deadline 300
             :assurance "safe")
            (my/lifeos-solver-negotiation-query
             request "minimal-project-defer-set" "e" "baseline"
             :candidate-project-ids '("project") :assurance "safe"))))
      (should (equal (mapcar (lambda (query) (alist-get 'kind query)) queries)
                     '("maximum-project-effort" "minimum-project-work-in-window"
                       "latest-safe-project-start"
                       "earliest-feasible-project-deadline"
                       "minimal-project-defer-set"))))))

(ert-deftest my/lifeos-solver-renders-project-negotiation-answers ()
  (with-temp-buffer
    (dolist (item
             '(((id . "a") (kind . "maximum-project-effort")
                (scope . "baseline") (feasibility . "PROVEN FEASIBLE")
                (projectId . "project") (assurance . "safe")
                (maximumEffortMinutes . 240) (testedMaximumEffortMinutes . 300)
                (assumptions . nil))
               ((id . "b") (kind . "minimum-project-work-in-window")
                (scope . "scenario") (feasibility . "PROVEN FEASIBLE")
                (projectId . "project") (assurance . "deadline-only")
                (minimumRequiredMinutes . 60) (testedStart . 100)
                (testedEnd . 200) (assumptions . nil))
               ((id . "c") (kind . "latest-safe-project-start")
                (scope . "baseline") (feasibility . "UNKNOWN")
                (projectId . "project") (latestStart . nil)
                (testedEarliestStart . 100) (testedLatestStart . 200)
                (assumptions . nil))
               ((id . "d") (kind . "earliest-feasible-project-deadline")
                (scope . "baseline") (feasibility . "PROVEN FEASIBLE")
                (projectId . "project") (assurance . "safe")
                (earliestDeadline . 200) (testedEarliestDeadline . 150)
                (testedLatestDeadline . 300) (assumptions . nil))
               ((id . "e") (kind . "minimal-project-defer-set")
                (scope . "baseline") (feasibility . "PROVEN FEASIBLE")
                (assurance . "safe") (candidateProjectIds . ("a" "b"))
                (deferredProjectIds . ("b")) (conflictProjectIds . ("a" "b"))
                (assumptions . nil))))
      (my/lifeos-solver--insert-negotiation-result item))
    (let ((text (buffer-string)))
      (dolist (expected '("Maximum effort" "Minimum required work"
                          "Latest safe start" "Earliest deadline"
                          "Minimal defer set" "Conflict-involved"))
        (should (string-match-p expected text))))))

(ert-deftest my/lifeos-solver-portfolio-review-renders-separate-status-and-drilldown ()
  (with-temp-buffer
    (org-mode)
    (insert "* Project")
    (let* ((marker (copy-marker (point-min)))
           (project (list :id "project" :key "id:project" :title "Project"
                          :marker marker :commitment 'committed
                          :definition-status 'coarse :deadline "<2026-10-20 Tue>"
                          :project-effort-minutes 300 :explicit-effort-minutes 60
                          :explicit-remaining-minutes 45
                          :unallocated-effort-minutes 240
                          :estimate-confidence "Medium"
                          :diagnostics (list (my/lifeos--diagnostic
                                              'review-estimate 'review
                                              "Review estimate"))))
           (task (list :id "task" :title "Task" :project-id "project"
                       :project-key "id:project" :marker marker))
            (orphan (list :id "orphan" :title "Orphan" :marker marker))
           (markers (make-hash-table :test #'equal))
            (analysis (list :projects (list project) :all-records (list task orphan)
                            :orphan-records (list orphan)))
           (request '((requestId . "request")
                      (tasks . [((id . "task") (projectId . "project")
                                 (workType . "explicit"))
                                ((id . "project:virtual:1")
                                 (projectId . "project") (workType . "virtual")
                                 (durationMinutes . 240))])))
           (context (list :analysis analysis :request request :source-markers markers))
           (project-result
            '((projectId . "project") (definitionStatus . "COARSE")
              (commitment . "COMMITTED") (isolatedFeasibility . "FEASIBLE")
              (proofKind . "CAPACITY FEASIBLE") (isolatedResult . nil)
              (borrowedPrerequisiteTaskIds . ("borrowed"))
              (borrowedPrerequisiteProjectIds . ("other"))
              (portfolioStatus . "CONFLICT-INVOLVED")
              (hardDeadlineMarginMinutes . 60) (safetyMarginMinutes . -30)
              (conflictTaskIds . ("task"))
              (conflictProjectIds . ("project" "other"))))
           (portfolio `((definitionStatus . "COMPLETE")
                        (feasibility . "PROVEN INFEASIBLE") (safety . nil)
                        (modeledProjectIds . ("project"))
                        (excludedProjectIds . nil) (modeledSubset . nil)
                        (globalResult . ,(my/lifeos-solver-test-solve-result))
                        (projectResults . (,project-result))))
           (result `((requestId . "request") (baselinePortfolio . ,portfolio)
                     (scenarioPortfolio . nil) (comparison . nil)
                     (negotiationResults . nil))))
      (puthash "project" marker markers)
      (puthash "task" marker markers)
      (puthash "orphan" marker markers)
      (with-temp-buffer
        (my/lifeos-solver--render-portfolio-review result context)
        (let ((text (buffer-string)))
          (dolist (expected '("Definition" "Isolated" "Portfolio"
                              "COARSE" "FEASIBLE" "CONFLICT-INVOLVED"
                              "Explicit work" "Virtual work"
                              "Borrowed prerequisites" "Conflicts"
                              "Orphan work" "groom-project"))
            (should (string-match-p expected text)))
          (goto-char (point-min))
          (search-forward "Project [project]")
          (should (button-at (match-beginning 0)))
          (search-forward "Orphan [orphan]")
           (should (button-at (match-beginning 0))))))))

(ert-deftest my/lifeos-portfolio-review-classifies-evidence-freshness ()
  (let* ((context '(:analysis (:projects nil)
                    :request ((requestId . "current"))))
         (result '((requestId . "current")))
         (old-result '((requestId . "old")))
         (my/lifeos-project-analysis-stale nil)
         (my/lifeos-solver-process nil))
    (should (equal (my/lifeos-solver--portfolio-evidence-state nil context)
                   "LOCAL ONLY"))
    (should (equal (my/lifeos-solver--portfolio-evidence-state result context)
                   "CURRENT"))
    (should (equal (my/lifeos-solver--portfolio-evidence-state old-result context)
                   "STALE"))
    (should (equal (my/lifeos-solver--portfolio-evidence-state nil nil)
                   "UNAVAILABLE"))
    (let* ((process (make-pipe-process :name "lifeos-portfolio-running"
                                       :noquery t))
           (my/lifeos-solver-process process))
      (unwind-protect
          (should (equal (my/lifeos-solver--portfolio-evidence-state
                          old-result context)
                         "RUNNING"))
        (delete-process process)))))

(ert-deftest my/lifeos-portfolio-review-is-self-describing-and-keyboard-operable ()
  (with-temp-buffer
    (org-mode)
    (insert "* Project")
    (let* ((marker (copy-marker (point-min)))
           (project (list :id "project" :key "id:project" :title "Project"
                          :marker marker :commitment 'committed
                          :definition-status 'incomplete
                          :diagnostics (list (my/lifeos--diagnostic
                                              'missing-project-id 'error
                                              "Project requires an ID"))))
           (context (list :analysis (list :projects (list project))
                          :request '((requestId . "local") (tasks . []))
                          :source-markers (make-hash-table :test #'equal))))
      (with-temp-buffer
        (my/lifeos-portfolio-review-mode)
        (let ((my/lifeos-project-analysis-stale nil)
              (inhibit-read-only t))
          (my/lifeos-solver--render-portfolio-review nil context))
        (let ((text (buffer-string)))
          (dolist (expected '("Portfolio Review" "READ-ONLY" "LOCAL ONLY"
                              "Planning status: NEED INFO" "r refresh"
                              "s schedule candidate" "Rows summarize projects"))
            (should (string-match-p expected text))))
        (goto-char (point-min))
        (search-forward "Project |")
        (search-forward "Project")
        (should (eq (get-text-property (point) 'lifeos-project-marker) marker))
        (dolist (binding '(("r" . my/lifeos-portfolio-review-refresh)
                           ("s" . my/lifeos-portfolio-review-open-schedule)
                           ("n" . my/lifeos-portfolio-review-next-project)
                           ("p" . my/lifeos-portfolio-review-previous-project)
                           ("RET" . my/lifeos-portfolio-review-visit-source)
                           ("g" . my/lifeos-portfolio-review-groom-project)
                           ("h" . my/lifeos-portfolio-review-help)
                           ("q" . quit-window)))
          (should (eq (lookup-key my/lifeos-portfolio-review-mode-map
                                  (kbd (car binding)))
                      (cdr binding))))))))

(ert-deftest my/lifeos-solver-configuration-template-is-complete-and-valid ()
  (let ((parsed (my/lifeos-solver--parse-configuration-rows
                 my/lifeos-solver--configuration-template-rows "test-template")))
    (should-not (plist-get parsed :issues))
    (should (= (length (cdr my/lifeos-solver--configuration-template-rows))
               (length my/lifeos-solver--configuration-keys)))))

(ert-deftest my/lifeos-settings-inserts-a-parser-valid-complete-table ()
  (my/lifeos-solver-test-with-org "* Recurring defaults\n"
    (let ((marker (copy-marker (point-min))))
      (my/lifeos-settings--insert-configuration-table marker)
      (let* ((rows (my/lifeos-solver--configuration-table marker))
             (parsed (my/lifeos-solver--parse-configuration-rows rows "inserted")))
        (should rows)
        (should-not (plist-get parsed :issues))))))

(ert-deftest my/lifeos-settings-cancellation-does-not-write-planning-source ()
  (let* ((directory (make-temp-file "lifeos-settings-" t))
         (org-directory directory)
         (file (expand-file-name "planning.org" directory)))
    (unwind-protect
        (progn
          (write-region "* Existing\n" nil file nil 'silent)
          (let ((before (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
            (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
              (should-error (my/lifeos-settings--visit-policy nil)
                            :type 'user-error))
            (should (equal before
                           (with-temp-buffer
                             (insert-file-contents file)
                             (buffer-string))))))
      (when-let* ((buffer (get-file-buffer file)))
        (set-buffer-modified-p nil)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest my/lifeos-solver-builds-all-five-discriminated-negotiation-kinds ()
  (let* ((request (my/lifeos-solver-test-request))
         (queries
          (list
           (my/lifeos-solver-negotiation-query
            request "maximum-deadline-only-discretionary-duration" "a" "baseline"
            :start 120 :maximum-end 300)
           (my/lifeos-solver-negotiation-query
            request "maximum-safe-discretionary-duration" "b" "baseline"
            :start 120 :maximum-end 300)
           (my/lifeos-solver-negotiation-query
            request "minimum-required-work-in-window" "c" "baseline"
            :start 120 :end 300 :assurance "safe")
           (my/lifeos-solver-negotiation-query
            request "latest-safe-discretionary-start" "d" "baseline"
            :duration-minutes 60 :earliest-start 120 :latest-end 300)
           (my/lifeos-solver-negotiation-query
            request "minimal-commitment-unlock-set" "e" "baseline"
            :candidate-commitment-ids '("fixed") :assurance "deadline-only"))))
    (should (equal (mapcar (lambda (query) (alist-get 'kind query)) queries)
                   '("maximum-deadline-only-discretionary-duration"
                     "maximum-safe-discretionary-duration"
                     "minimum-required-work-in-window"
                     "latest-safe-discretionary-start"
                     "minimal-commitment-unlock-set")))
    (should (equal (alist-get 'candidateCommitmentIds (car (last queries)))
                   ["fixed"]))))

(ert-deftest my/lifeos-solver-builders-and-report-do-not-mutate-org ()
  (my/lifeos-solver-test-with-org
      "* TODO Task\n:PROPERTIES:\n:ID: task\n:END:\n"
    (set-buffer-modified-p nil)
    (let ((request (my/lifeos-solver-test-request)))
      (my/lifeos-solver-scenario-estimate-change request "task" 60)
      (my/lifeos-solver-negotiation-query
       request "maximum-safe-discretionary-duration" "q" "baseline"
       :start 120 :maximum-end 300))
    (should-not (buffer-modified-p))))

(ert-deftest my/lifeos-solver-discrepancy-classifies-stable-ids ()
  (let* ((time (lambda (minute) (seconds-to-time (* minute 60))))
         (forecast
          (list :placements
                (list (list :id "same" :start (funcall time 200))
                      (list :id "different" :start (funcall time 300))
                      (list :id "heuristic" :start (funcall time 400)))
                :failures (list (list :id "solver" :reason "heuristic constraint"))))
         (analysis
          (list :all-records
                (mapcar (lambda (id) (list :id id :title (capitalize id)))
                        '("same" "different" "heuristic" "solver"))))
         (request
          '((tasks . [((id . "same")) ((id . "different")) ((id . "solver"))])))
         (context (list :forecast forecast :analysis analysis :request request))
         (result
          '((baseline . ((feasibility . "PROVEN FEASIBLE")
                         (placements . (((taskId . "same") (start . 200))
                                        ((taskId . "different") (start . 315))
                                        ((taskId . "solver") (start . 500))))))))
         (items (my/lifeos-solver-discrepancies result context)))
    (should (equal (mapcar (lambda (item)
                             (cons (plist-get item :id)
                                   (plist-get item :classification)))
                           items)
                   '(("different" . different-placement)
                     ("heuristic" . heuristic-only)
                     ("same" . same-placement)
                     ("solver" . solver-only))))
    (should (string-match-p
             "heuristic rejected"
             (plist-get (car (last items)) :expected-difference)))))

(ert-deftest my/lifeos-solver-discrepancy-classifies-unknown-solver ()
  (let* ((context
          (list :forecast
                (list :placements
                      (list (list :id "task" :start (seconds-to-time (* 200 60)))))
                :request '((tasks . [((id . "task"))]))))
         (items (my/lifeos-solver-discrepancies
                 '((baseline . ((feasibility . "UNKNOWN") (placements . ()))))
                 context)))
    (should (eq (plist-get (car items) :classification) 'solver-unknown))))

(ert-deftest my/lifeos-solver-report-renders-sections-titles-and-local-times ()
  (let* ((analysis (list :all-records
                         (list (list :id "task" :title "Write report"))))
         (context
          (list :analysis analysis :forecast '(:placements nil :failures nil)
                :captured-at (current-time)
                :request '((scenario . :null) (negotiationQueries . []))
                :source-markers (make-hash-table :test #'equal)))
         (solve
          '((feasibility . "PROVEN FEASIBLE") (safety . "SAFE")
            (resilience . "RESILIENT")
            (placements . (((taskId . "task") (start . 200) (end . 260)
                            (kind . "proposed"))))
            (reservePlacements . ()) (sleepPlacements . ())
            (intentions . ()) (conflicts . ()) (assumptions . ("Assume"))
             (unlockedCommitmentIds . ())
             (stressResults . (((id . "stress")
                               (feasibility . "PROVEN FEASIBLE"))))))
         (negotiations
          '(((id . "a") (kind . "maximum-deadline-only-discretionary-duration")
             (scope . "baseline") (feasibility . "PROVEN FEASIBLE")
             (maximumDurationMinutes . 60) (testedStart . 200)
             (testedMaximumEnd . 300) (assumptions . ()))
            ((id . "b") (kind . "maximum-safe-discretionary-duration")
             (scope . "baseline") (feasibility . "UNKNOWN")
             (maximumDurationMinutes) (testedStart . 200)
             (testedMaximumEnd . 300) (assumptions . ()))
            ((id . "c") (kind . "minimum-required-work-in-window")
             (scope . "baseline") (assurance . "safe")
             (feasibility . "PROVEN FEASIBLE") (minimumRequiredMinutes . 30)
             (testedStart . 200) (testedEnd . 300) (assumptions . ()))
            ((id . "d") (kind . "latest-safe-discretionary-start")
             (scope . "baseline") (feasibility . "PROVEN FEASIBLE")
             (latestStart . 240) (testedDurationMinutes . 30)
             (testedEarliestStart . 200) (testedLatestEnd . 300)
             (assumptions . ()))
            ((id . "e") (kind . "minimal-commitment-unlock-set")
             (scope . "baseline") (assurance . "safe")
             (feasibility . "PROVEN FEASIBLE")
             (candidateCommitmentIds . ["task"])
             (unlockedCommitmentIds . ["task"]) (assumptions . ()))))
         (my/lifeos-solver-current-request-id "report")
         (my/lifeos-solver-last-good-request-context context)
         (my/lifeos-solver-last-good-result
           `((protocolVersion . "lifeos-planning/v3")
             (solverVersion . "lifeos-z3/0.3.0+z3-solver/5.2.0")
            (requestId . "report") (status . "ok") (baseline . ,solve)
            (scenario) (comparison) (negotiationResults . ,negotiations)))
         (my/lifeos-solver-last-error nil)
         (my/lifeos-solver-process nil))
    (with-temp-buffer
      (my/lifeos-solver--render-report)
      (let ((text (buffer-string)))
        (should (string-match-p "READ-ONLY / SHADOW" text))
        (should (string-match-p "Write report \\[task\\]" text))
        (should (string-match-p "Task placements" text))
        (should (string-match-p "Stress results" text))
        (should (string-match-p "Scenario comparison" text))
        (should (string-match-p "Heuristic vs solver" text))
        (dolist (kind '("maximum-deadline-only-discretionary-duration"
                        "maximum-safe-discretionary-duration"
                        "minimum-required-work-in-window"
                        "latest-safe-discretionary-start"
                        "minimal-commitment-unlock-set"))
          (should (string-match-p kind text)))
        (should-not (string-match-p "start . 200" text))))))

(ert-deftest my/lifeos-solver-report-source-title-is-clickable ()
  (let ((source (generate-new-buffer " *lifeos-source-button*")))
    (unwind-protect
        (with-current-buffer source
          (insert "Task")
          (let ((markers (make-hash-table :test #'equal)))
            (puthash "task" (copy-marker (point-min)) markers)
            (with-temp-buffer
              (my/lifeos-solver--insert-source
               (list :analysis
                     (list :all-records (list (list :id "task" :title "Task title")))
                     :source-markers markers)
               "task")
              (should (button-at (point-min)))
              (should (equal (buffer-string) "Task title [task]")))))
      (kill-buffer source))))

(ert-deftest my/lifeos-solver-report-shows-running-stale-and-error-context ()
  (let* ((process (make-pipe-process :name "lifeos-report-running" :noquery t))
         (my/lifeos-solver-process process)
         (my/lifeos-solver-current-request-id "new")
         (my/lifeos-solver-last-error "latest request failed")
         (my/lifeos-solver-last-good-request-context
          '(:request ((scenario . :null) (negotiationQueries . []))))
         (my/lifeos-solver-last-good-result
            '((protocolVersion . "lifeos-planning/v3")
              (solverVersion . "lifeos-z3/0.3.0+z3-solver/5.2.0")
            (requestId . "old") (status . "ok") (baseline) (scenario)
            (comparison) (negotiationResults . ()))))
    (unwind-protect
        (with-temp-buffer
          (my/lifeos-solver--render-report)
          (should (string-match-p "RUNNING; STALE result shown; ERROR"
                                  (buffer-string)))
          (should (string-match-p "latest request failed" (buffer-string))))
      (delete-process process))))

(ert-deftest my/lifeos-solver-hard-fails-ungroomed-mandatory-headings-absent-from-graph ()
  (my/lifeos-solver-test-with-org
      "* TODO Deadline\nDEADLINE: <2026-10-20 Tue>\n* NEXT Appointment\nSCHEDULED: <2026-10-15 Thu 10:00>\n"
    (let (grooming)
      (goto-char (point-min))
      (push (list :marker (copy-marker (point)) :todo "TODO"
                  :diagnostics '(invalid))
            grooming)
      (search-forward "* NEXT")
      (beginning-of-line)
      (push (list :marker (copy-marker (point)) :todo "NEXT"
                  :diagnostics '(invalid))
            grooming)
      (my/lifeos-solver-test-with-normalization-stubs
        (cl-letf (((symbol-function 'my/lifeos--grooming-records)
                   (lambda (scope)
                     (should (eq scope 'all))
                     grooming)))
          (let ((issues (append
                         (alist-get 'hardIssues
                                    (my/lifeos-solver-normalize
                                     (list :all-records nil :projects nil)
                                     nil (encode-time 0 0 10 14 10 2026)))
                         nil)))
            (should (= (length
                        (seq-filter
                         (lambda (issue) (string-match-p "ungroomed" issue))
                         issues))
                       2))))))))

(ert-deftest my/lifeos-solver-normalization-failure-supersedes-running-request ()
  (let* ((process (make-pipe-process :name "lifeos-normalize-failure" :noquery t))
         (my/lifeos-solver-process process)
         (my/lifeos-solver-current-request-id "old")
         (my/lifeos-solver-shadow-enabled t))
    (unwind-protect
        (cl-letf (((symbol-function 'my/lifeos-solver--snapshot)
                   (lambda (&rest _) (error "normalization failed"))))
          (should-error (my/lifeos-solver-request-shadow) :type 'error)
          (should-not my/lifeos-solver-current-request-id)
          (should-not my/lifeos-solver-process)
          (should-not (process-live-p process)))
      (when (process-live-p process) (delete-process process)))))

(ert-deftest my/lifeos-solver-stress-reservations-use-free-availability ()
  (let* ((records (list (my/lifeos-solver-test-record "task" :minutes 60)))
         (availability '[((start . 0) (end . 180) (modes . ["Deep"]))])
         (busy '[((start . 0) (end . 120))])
         (configuration '(:stress-estimate-enabled t :stress-estimate-percent 25
                          :stress-deep-enabled t :stress-appointment-enabled t
                          :stress-appointment-minutes 60))
         (result (my/lifeos-solver--stress-profiles
                  records availability busy configuration))
         (profiles (append (car result) nil)))
    (should-not (cdr result))
    (dolist (profile (cdr profiles))
      (let ((reservation (aref (alist-get 'reservations
                                           (alist-get 'scenario profile)) 0)))
        (should (= (alist-get 'start reservation) 120))
        (should (= (alist-get 'end reservation) 180))))
    (let* ((scenario (alist-get 'scenario (car profiles)))
           (multiplier (aref (alist-get 'estimateMultipliers scenario) 0)))
      (should (equal (alist-get 'estimateChanges scenario) []))
      (should (= (alist-get 'percentage multiplier) 25)))))

(ert-deftest my/lifeos-solver-invalid-stress-profile-only-discloses-assumption ()
  (my/lifeos-solver-test-with-normalization-stubs
    (cl-letf (((symbol-function 'my/lifeos-solver--configuration)
               (lambda (&rest _)
                 (list :values
                       (plist-put (my/lifeos-solver--configuration-defaults)
                                  :stress-estimate-enabled t)
                       :source-id "test" :issues nil))))
      (let* ((request (my/lifeos-solver-normalize
                       (list :all-records nil :projects nil)
                       nil (encode-time 0 0 10 14 10 2026)))
             (hard (append (alist-get 'hardIssues request) nil))
             (assumptions (append (alist-get 'inputAssumptions request) nil)))
        (should-not (seq-some (lambda (text)
                                (string-match-p "Estimate-overrun" text))
                              hard))
        (should (seq-some (lambda (text)
                            (string-match-p "Estimate-overrun.*omitted" text))
                          assumptions))))))

(ert-deftest my/lifeos-solver-current-night-sleep-is-clipped-or-rejected ()
  (let* ((sleep '(:earliest-start "22:00" :latest-end "09:00"
                  :minimum-minutes 480))
         (end (encode-time 0 0 12 15 10 2026))
         (start (encode-time 0 0 23 14 10 2026))
         (result (my/lifeos-solver--sleep-blocks start end sleep))
         (block (aref (car result) 0)))
    (should (= (alist-get 'envelopeStart block)
               (my/lifeos-solver--minute start)))
    (should-not (cdr result))
    (let* ((late-start (encode-time 0 0 2 15 10 2026))
           (late-result (my/lifeos-solver--sleep-blocks late-start end sleep)))
      (should (equal (car late-result) []))
      (should (string-match-p "cannot fit" (car (cdr late-result)))))))

(ert-deftest my/lifeos-solver-weekly-reserve-is-anchored-to-monday ()
  (let* ((start (encode-time 0 0 0 14 10 2026))
         (end (encode-time 0 0 0 18 10 2026))
         (available-start (my/lifeos-solver--minute
                           (encode-time 0 0 9 14 10 2026)))
         (available-end (my/lifeos-solver--minute
                         (encode-time 0 0 17 14 10 2026)))
         (availability `[((start . ,available-start) (end . ,available-end))])
         (configuration '(:daily-reserve 0 :weekly-reserve 60 :reserve-block 60))
         (result (my/lifeos-solver--reserve-blocks
                  start end availability configuration))
         (block (aref (car result) 0)))
    (should (string-prefix-p "weekly-reserve:2026-10-12"
                             (alist-get 'id block)))
    (should (= (alist-get 'envelopeStart block)
               (my/lifeos-solver--minute start)))
    (should-not (cdr result))))

(ert-deftest my/lifeos-solver-calendar-entry-id-prevents-simultaneous-collisions ()
  (let* ((directory (make-temp-file "lifeos-calendar-id-" t))
         (org-directory directory)
         (file (expand-file-name "calendar.org" directory))
         (configuration '(:travel-defaults nil :unknown-travel (0 . 0)
                          :remote-setup 0)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* One\n:PROPERTIES:\n:entry-id: event-one\n:GCAL_BUSY: yes\n:ATTENDANCE: in-person\n:END:\n<2026-10-14 Wed 10:00-11:00>\n"
                    "* Two\n:PROPERTIES:\n:entry-id: event-two\n:GCAL_BUSY: yes\n:ATTENDANCE: in-person\n:END:\n<2026-10-14 Wed 10:00-11:00>\n"))
          (let* ((result (my/lifeos-solver--calendar-blocks
                          (encode-time 0 0 0 14 10 2026)
                          (encode-time 0 0 0 15 10 2026)
                          configuration))
                 (ids (mapcar (lambda (block) (alist-get 'id block))
                              (append (car result) nil))))
            (should (= (length ids) 2))
            (should (= (length ids) (length (delete-dups ids))))))
      (when-let* ((buffer (get-file-buffer file)))
        (set-buffer-modified-p nil)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest my/lifeos-solver-malformed-project-buffer-is-a-safety-issue ()
  (my/lifeos-solver-test-with-org
      "* Project\n:PROPERTIES:\n:ID: project\n:SAFETY_BUFFER: nope\n:END:\n"
    (let ((project (list :id "project" :marker (copy-marker (point-min)))))
      (my/lifeos-solver-test-with-normalization-stubs
        (let* ((request (my/lifeos-solver-normalize
                         (list :all-records nil :projects (list project))
                         nil (encode-time 0 0 10 14 10 2026)))
               (safety (append (alist-get 'safetyIssues request) nil))
               (project-json (aref (alist-get 'projects request) 0)))
          (should (seq-some (lambda (issue)
                              (string-match-p "malformed SAFETY_BUFFER" issue))
                            safety))
          (should (eq (alist-get 'safetyBufferMinutes project-json) :null)))))))

(ert-deftest my/lifeos-solver-source-button-uses-captured-marker ()
  (let ((captured (generate-new-buffer " *lifeos-captured-source*"))
        (replacement (generate-new-buffer " *lifeos-replacement-source*"))
        visited)
    (unwind-protect
        (let ((context-markers (make-hash-table :test #'equal))
              (my/lifeos-solver-source-markers (make-hash-table :test #'equal)))
          (with-current-buffer captured (insert "Captured"))
          (with-current-buffer replacement (insert "Replacement"))
          (puthash "task" (with-current-buffer captured (copy-marker (point-min)))
                   context-markers)
          (puthash "task" (with-current-buffer replacement (copy-marker (point-min)))
                   my/lifeos-solver-source-markers)
          (cl-letf (((symbol-function 'my/lifeos-solver--visit-marker)
                     (lambda (marker id) (setq visited (cons marker id)))))
            (with-temp-buffer
              (my/lifeos-solver--insert-source
               (list :analysis (list :all-records
                                     (list (list :id "task" :title "Task")))
                     :source-markers context-markers)
               "task")
              (button-activate (button-at (point-min)))))
          (should (equal (cdr visited) "task"))
          (should (eq (marker-buffer (car visited)) captured)))
      (kill-buffer captured)
      (kill-buffer replacement))))

(ert-deftest my/lifeos-solver-rejects-malformed-success-results ()
  (let ((baseline-response (my/lifeos-solver-test-response "request"))
        (query-response (my/lifeos-solver-test-response "request")))
    (setf (alist-get 'placements (alist-get 'baseline baseline-response))
          '(((taskId . "task") (start . "bad"))))
    (should (string-match-p
             "malformed task placements"
             (my/lifeos-solver--response-validation-error
              baseline-response "request")))
    (setf (alist-get 'negotiationResults query-response)
          '(((id . "q") (kind . "maximum-safe-discretionary-duration")
             (scope . "baseline") (feasibility . "PROVEN FEASIBLE")
             (assumptions . nil))))
    (should (string-match-p
             "malformed negotiation result"
              (my/lifeos-solver--response-validation-error
               query-response "request")))))

(ert-deftest my/lifeos-solver-wait-until-releases-future-waiting-work ()
  (my/lifeos-solver-test-with-org
      "* WAITING Future\n:PROPERTIES:\n:WAIT_UNTIL: <2026-10-20 Tue 09:00>\n:END:\n* WAITING Mandatory\n:PROPERTIES:\n:WAIT_UNTIL: <2026-10-10 Sat>\n:END:\n* WAITING Optional unresolved\n:PROPERTIES:\n:WAIT_UNTIL: not-a-date\n:END:\n"
    (let (future-marker mandatory-marker unresolved-marker)
      (goto-char (point-min))
      (setq future-marker (copy-marker (point)))
      (search-forward "* WAITING Mandatory")
      (beginning-of-line)
      (setq mandatory-marker (copy-marker (point)))
      (search-forward "* WAITING Optional unresolved")
      (beginning-of-line)
      (setq unresolved-marker (copy-marker (point)))
      (my/lifeos-solver-test-with-normalization-stubs
        (let* ((future (my/lifeos-solver-test-record
                        "future" :state "WAITING" :marker future-marker))
               (mandatory (my/lifeos-solver-test-record
                           "mandatory" :state "WAITING" :marker mandatory-marker
                           :deadline "<2026-10-21 Wed>"
                           :deadline-end (encode-time 0 0 0 22 10 2026)))
               (unresolved (my/lifeos-solver-test-record
                            "unresolved" :state "WAITING" :marker unresolved-marker))
               (request (my/lifeos-solver-normalize
                         (list :all-records (list future mandatory unresolved)
                               :projects nil)
                         nil (encode-time 0 0 10 14 10 2026)))
               (tasks (append (alist-get 'tasks request) nil))
               (future-json (seq-find (lambda (item)
                                        (equal (alist-get 'id item) "future"))
                                      tasks))
               (mandatory-json (seq-find (lambda (item)
                                           (equal (alist-get 'id item) "mandatory"))
                                         tasks)))
          (should (equal (mapcar (lambda (item) (alist-get 'id item)) tasks)
                         '("future" "mandatory")))
          (should (numberp (alist-get 'releaseTime future-json)))
          (should (eq (alist-get 'unresolvedWaiting future-json) :false))
          (should (eq (alist-get 'releaseTime mandatory-json) :null))
          (should (eq (alist-get 'unresolvedWaiting mandatory-json) t)))))))

(ert-deftest my/lifeos-solver-calendar-role-counts-events-not-travel ()
  (let* ((directory (make-temp-file "lifeos-calendar-role-" t))
         (org-directory directory)
         (file (expand-file-name "calendar.org" directory))
         (markers (make-hash-table :test #'equal)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Class\n:PROPERTIES:\n:ID: class\n:GCAL_BUSY: yes\n:CALENDAR_ROLE: School\n:ATTENDANCE: in-person\n:TRAVEL_BEFORE: 1:00\n:TRAVEL_AFTER: 1:00\n:END:\n<2026-10-14 Wed 10:00-11:00>\n"))
          (cl-letf (((symbol-function 'my/lifeos-intentions-for-week)
                     (lambda (_)
                       (list (list :id "class" :name "Class" :minimum nil
                                   :target 60 :maximum nil
                                   :selector '(calendar-role "School")
                                   :selector-text
                                   "(calendar-role \"School\")"))))
                    ((symbol-function 'my/lifeos--week-times)
                     (lambda (_) (list (encode-time 0 0 0 12 10 2026)
                                        (encode-time 0 0 0 19 10 2026)))))
            (let* ((result (my/lifeos-solver--intentions
                            "2026-10-12" nil nil markers))
                   (intention (aref (plist-get result :intentions) 0))
                   (evidence (append (alist-get 'matchEvidence intention) nil)))
              (should (= (alist-get 'actualMinutes intention) 60))
              (should (seq-some (lambda (item)
                                  (equal (alist-get 'kind item) "calendar-role"))
                                evidence))
              (should (= (hash-table-count markers) 1)))))
      (when-let* ((buffer (get-file-buffer file)))
        (set-buffer-modified-p nil)
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest my/lifeos-solver-ephemeral-scenario-composes-clears-and-runs ()
  (let* ((request (my/lifeos-solver-test-request))
         (scenario (my/lifeos-solver-scenario-reserve request 120 180 "scenario-busy"))
         (scenario (my/lifeos-solver-scenario-estimate-change
                    request "task" 90 scenario))
         (my/lifeos-solver-current-scenario scenario)
         submitted)
    (cl-letf (((symbol-function 'my/lifeos-solver--snapshot)
               (lambda () (list :request (copy-tree request))))
              ((symbol-function 'my/lifeos-solver--start-request)
               (lambda (context) (setq submitted (plist-get context :request)))))
      (my/lifeos-solver-scenario-run-command)
      (should (= (length (alist-get 'reservations
                                    (alist-get 'scenario submitted))) 1))
      (should (= (length (alist-get 'estimateChanges
                                    (alist-get 'scenario submitted))) 1))
      (my/lifeos-solver-scenario-clear-command)
      (should-not my/lifeos-solver-current-scenario))))

(ert-deftest my/lifeos-solver-negotiation-can-use-current-scenario-scope ()
  (let* ((request (my/lifeos-solver-test-request))
         (my/lifeos-solver-current-scenario
          (my/lifeos-solver-scenario-reserve request 120 180 "scenario-busy"))
         (minutes '(120 300))
         submitted)
    (cl-letf (((symbol-function 'my/lifeos-solver--snapshot)
               (lambda () (list :request (copy-tree request))))
              ((symbol-function 'completing-read) (lambda (&rest _) "scenario"))
              ((symbol-function 'my/lifeos-solver--read-minute)
               (lambda (&rest _) (prog1 (car minutes) (setq minutes (cdr minutes)))))
              ((symbol-function 'my/lifeos-solver--start-request)
               (lambda (context) (setq submitted (plist-get context :request)))))
      (my/lifeos-solver-negotiate "maximum-safe-discretionary-duration")
      (should (equal (alist-get 'scenario submitted)
                     my/lifeos-solver-current-scenario))
      (should (equal (alist-get 'scope
                                (aref (alist-get 'negotiationQueries submitted) 0))
                     "scenario")))))

(ert-deftest my/lifeos-solver-report-renders-optional-protocol-extensions ()
  (with-temp-buffer
    (let ((result (my/lifeos-solver-test-solve-result)))
      (setf (alist-get 'deadlineMargins result)
            '(((taskId . "task") (marginMinutes . 45)))
            (alist-get 'conflicts result)
            '(((constraintId . "c") (sourceId . "task") (kind . "deadline")
               (message . "tight") (minimumRelaxationMinutes . 30))))
      (my/lifeos-solver--insert-solve-result "Baseline" result nil)
      (my/lifeos-solver--insert-comparison
       '((interpretation . "changed")
         (placementDeltas . (((taskId . "task") (minutes . 15))))) nil)
      (should (string-match-p "Deadline margins" (buffer-string)))
      (should (string-match-p "minimumRelaxationMinutes 30" (buffer-string)))
      (should (string-match-p "placementDeltas" (buffer-string))))))

(ert-deftest my/lifeos-solver-estimate-stress-round-trips-through-real-cli ()
  (let* ((root (my/lifeos-solver--solver-root))
         (fixture (expand-file-name "test/fixtures/sat.json" root))
         (command (list "npm" "--prefix" root "run" "--silent" "solve"))
         (request (json-parse-string
                   (with-temp-buffer
                     (insert-file-contents fixture)
                     (buffer-string))
                   :object-type 'alist :array-type 'array
                   :null-object :null :false-object :false))
         (configuration '(:stress-estimate-enabled t
                          :stress-estimate-percent 25
                          :stress-deep-enabled nil
                          :stress-appointment-enabled nil))
         (records '((:id "research" :minutes 120)
                    (:id "draft" :minutes 30)))
         (profiles (car (my/lifeos-solver--stress-profiles
                         records nil nil configuration)))
         (stderr-file (make-temp-file "lifeos-solver-cli-stderr-")))
    (setf (alist-get 'requestId request) "ert-estimate-stress-cli"
          (alist-get 'stressProfiles request) profiles)
    (unwind-protect
        (with-temp-buffer
          (insert (json-serialize request))
          (let ((status (apply #'call-process-region
                               (point-min) (point-max) (car command)
                               t (list t stderr-file) nil (cdr command))))
            (should (zerop status))
            (let* ((response (json-parse-string
                              (buffer-string) :object-type 'alist
                              :array-type 'array :null-object nil
                              :false-object nil))
                   (stress (alist-get 'stressResults
                                      (alist-get 'baseline response))))
              (should (equal (alist-get 'status response) "ok"))
              (should (equal (alist-get 'id (aref stress 0))
                             "stress:estimate-overrun")))))
      (delete-file stderr-file))))

(provide 'lifeos-solver-test)
;;; lifeos-solver-test.el ends here
