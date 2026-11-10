;;; lifeos-planning-test.el --- Tests for LifeOS planning -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(load (expand-file-name "lifeos-planning.el"
                        (file-name-directory
                         (or load-file-name buffer-file-name)))
      nil t)
(load (expand-file-name "lifeos-forecast.el"
                        (file-name-directory
                         (or load-file-name buffer-file-name)))
      nil t)

(defmacro my/lifeos-test-with-org (content &rest body)
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

(defmacro my/lifeos-test-with-agenda-file (content &rest body)
  "Evaluate BODY with CONTENT as the only temporary agenda file."
  (declare (indent 1) (debug t))
  `(let* ((file (make-temp-file "lifeos-test-" nil ".org" ,content))
          (org-agenda-files (list file)))
     (unwind-protect
         (progn ,@body)
       (when-let* ((buffer (get-file-buffer file)))
         (kill-buffer buffer))
       (delete-file file))))

(defmacro my/lifeos-test-with-planning (content &rest body)
  "Evaluate BODY with CONTENT in a temporary planning.org."
  (declare (indent 1) (debug t))
  `(let* ((directory (make-temp-file "lifeos-planning-" t))
          (org-directory directory)
          (file (expand-file-name "planning.org" directory)))
     (unwind-protect
         (progn
           (write-region ,content nil file nil 'silent)
           ,@body)
       (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
       (delete-directory directory t))))

(defconst my/lifeos-test-valid-task
  "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 0:30
:ORIGINAL_EFFORT: 0:30
:IMPACT: High
:WORK_MODE: Deep
:END:
")

(ert-deftest my/lifeos-unclassified-task-needs-no-fixed-classification ()
  (my/lifeos-test-with-org my/lifeos-test-valid-task
    (should (my/lifeos-task-eligible-p '("TODO" "NEXT")))
    (should-not (seq-find (lambda (diagnostic)
                           (eq (plist-get diagnostic :code) 'invalid-domain))
                         (my/lifeos-task-diagnostics)))))

(ert-deftest my/lifeos-task-scaffolding-and-records-omit-domain ()
  (my/lifeos-test-with-org "* TODO [#A] Capture #task\n"
    (let ((file (make-temp-file "lifeos-no-classification-")))
      (unwind-protect
          (let ((buffer-file-name file))
            (my/lifeos-scaffold-task)
            (should-not (org-entry-get nil "DOMAIN"))
            (dolist (property '("EFFORT" "ORIGINAL_EFFORT" "IMPACT" "WORK_MODE"))
              (should (equal (org-entry-get nil property) ""))))
        (delete-file file))))
  (my/lifeos-test-with-agenda-file my/lifeos-test-valid-task
    (cl-letf (((symbol-function 'org-id-update-id-locations)
               (lambda (&rest _) nil)))
      (let ((record (car (my/lifeos--task-records))))
        (should-not (plist-member record :domain))))))

(ert-deftest my/lifeos-selector-language-is-restricted-source-aware-and-composable ()
  (let ((task '(:source-type task :id "task" :tags ("reading")
                :properties (("CONTEXT" . "library")) :work-mode "Deep"
                :project-id "degree" :project-tags ("school")
                :project-properties (("TERM" . "fall"))))
        (calendar '(:source-type calendar :calendar-role "school")))
    (dolist (selector '((tag "reading") (project-tag "school")
                        (project-id "degree") (prop "CONTEXT" "library")
                        (project-prop "TERM" "fall") (work-mode "Deep")
                        (source task)
                        (and (source task) (not (work-mode "Errand")))
                        (or (calendar-role "school") (project-tag "school"))))
      (should (my/lifeos-selector-match-p selector task)))
    (should (my/lifeos-selector-match-p
             '(or (project-tag "school") (calendar-role "school")) calendar))
    (should-not (my/lifeos-selector-match-p '(source task) calendar))
    (should-error (my/lifeos-read-selector "(domain \"School\")"))
    (should-error (my/lifeos-read-selector "(progn (delete-file \"no\"))"))
    (should-error (my/lifeos-read-selector "(tag \"reading\") trailing"))))

(ert-deftest my/lifeos-weekly-intentions-replace-recurring-intentions ()
  (my/lifeos-test-with-planning
      "* Recurring defaults\n** Intentions\n| Name | Min | Target | Max | Selector |\n| Reading | 1:00 | 2:00 | 3:00 | (tag \"reading\") |\n* Week\n:PROPERTIES:\n:WEEK_START: 2026-10-12\n:END:\n** Intentions\n| Name | Min | Target | Max | Selector |\n| Degree | 2:00 | 4:00 | 6:00 | (project-id \"degree\") |\n"
    (should (equal (mapcar (lambda (row) (plist-get row :name))
                           (my/lifeos-intentions-for-week "2026-10-12"))
                   '("Degree")))
    (should (equal (mapcar (lambda (row) (plist-get row :name))
                           (my/lifeos-intentions-for-week "2026-10-19"))
                   '("Reading")))))

(ert-deftest my/lifeos-intention-ledger-credits-overlapping-rows-independently ()
  (let* ((record '(:source-type task :id "essay" :state "TODO" :minutes 60
                   :tags ("reading") :project-id "degree"))
         (by-id (make-hash-table :test #'equal))
         (analysis (list :all-records (list record) :by-id by-id))
         (start (my/lifeos--date-time "2026-10-12" "09:00"))
         (forecast (list :placements
                         (list (list :id "essay" :kind 'proposed
                                     :start start :minutes 60))))
         (intentions '((:id "a" :name "Reading" :target 120
                        :selector (tag "reading") :selector-text "(tag reading)")
                       (:id "b" :name "Degree" :target 180
                        :selector (project-id "degree")
                        :selector-text "(project-id degree)"))))
    (puthash "essay" record by-id)
    (cl-letf (((symbol-function 'my/lifeos-intentions-for-week)
               (lambda (_) intentions))
              ((symbol-function 'my/lifeos--calendar-intention-minutes)
               (lambda (&rest _) 0)))
      (let ((rows (my/lifeos-intention-ledger "2026-10-12" forecast analysis)))
        (should (equal (mapcar (lambda (row) (plist-get row :remaining)) rows)
                       '(60 60)))
        (should (equal (mapcar (lambda (row) (plist-get row :proposed)) rows)
                       '(60 60)))))))

(ert-deftest my/lifeos-calendar-intention-accounting-is-timed-clipped-and-composable ()
  (let* ((directory (make-temp-file "lifeos-calendar-" t))
         (org-directory directory)
         (file (expand-file-name "calendar.org" directory))
         (start (my/lifeos--date-time "2026-10-12" "10:00"))
         (end (my/lifeos--date-time "2026-10-12" "12:00")))
    (unwind-protect
        (progn
          (write-region
           "* Timed\n:PROPERTIES:\n:CALENDAR_ROLE: school\n:END:\n<2026-10-12 Mon 09:30-11:30>\n* All day\n:PROPERTIES:\n:CALENDAR_ROLE: school\n:END:\n<2026-10-12 Mon>\n"
           nil file nil 'silent)
          (should (= (my/lifeos--calendar-intention-minutes
                      '(or (project-tag "school") (calendar-role "school"))
                      start end)
                     90)))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest my/lifeos-todo-descendants-are-named ()
  (my/lifeos-test-with-org
      "* TODO Parent #task
** DONE Finished child
** Notes
*** TODO Nested child
"
    (should (equal (my/lifeos--todo-descendant-headings)
                   '("Finished child" "Nested child")))))

(ert-deftest my/lifeos-non-leaf-task-has-structured-error ()
  (my/lifeos-test-with-org
      "* TODO [#A] Parent #task
:PROPERTIES:
:ID: parent-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
** TODO Child
"
    (let ((diagnostic
           (seq-find (lambda (item)
                       (eq (plist-get item :code) 'non-leaf-task))
                     (my/lifeos-task-diagnostics))))
      (should diagnostic)
      (should (eq (plist-get diagnostic :severity) 'error))
      (should (equal (plist-get diagnostic :data) '("Child"))))))

(ert-deftest my/lifeos-completed-aggregate-remains-structurally-invalid ()
  (my/lifeos-test-with-org
      "* DONE Parent #task
** DONE Child
"
    (should-not (my/lifeos-executable-leaf-p))
    (should (eq (plist-get (car (my/lifeos-task-diagnostics)) :code)
                'non-leaf-task))))

(ert-deftest my/lifeos-groom-refuses-aggregate-heading ()
  (my/lifeos-test-with-org
      "* TODO Parent
** TODO Child
"
    (should-error (my/lifeos-groom-task)
                  :type 'user-error)))

(ert-deftest my/lifeos-state-guard-blocks-aggregate-task ()
  (my/lifeos-test-with-org
      "* TODO Parent #task
** TODO Child
"
    (let ((change (list :type 'todo-state-change
                        :to "NEXT"
                        :position (point))))
      (should-not (my/lifeos-block-dependent-state-change change)))))

(ert-deftest my/lifeos-valid-leaf-is-eligible ()
  (my/lifeos-test-with-org my/lifeos-test-valid-task
    (should (my/lifeos-task-eligible-p '("TODO" "NEXT")))))

(ert-deftest my/lifeos-scaffold-task-creates-identity-and-empty-properties ()
  (my/lifeos-test-with-org
      "* TODO Capture this
"
    (let ((file (make-temp-file "lifeos-scaffold-")))
      (unwind-protect
          (let ((buffer-file-name file))
            (let ((id (my/lifeos-scaffold-task)))
              (should (stringp id))
              (should (equal (org-entry-get nil "ID") id))
              (should (equal (org-get-heading t t t t) "Capture this #task"))
              (dolist (property '("EFFORT" "ORIGINAL_EFFORT" "IMPACT"
                                  "WORK_MODE"))
                (should (equal (org-entry-get nil property) "")))))
        (delete-file file)))))

(ert-deftest my/lifeos-scaffold-task-preserves-existing-properties ()
  (my/lifeos-test-with-org
      "* TODO Existing #task
 :PROPERTIES:
 :ID: existing-id
 :EFFORT: 1:00
 :CONTEXT: Library
 :END:
"
    (should (equal (my/lifeos-scaffold-task) "existing-id"))
    (should (equal (org-entry-get nil "ID") "existing-id"))
    (should (equal (org-entry-get nil "EFFORT") "1:00"))
    (should (equal (org-entry-get nil "CONTEXT") "Library"))
    (should (equal (org-entry-get nil "ORIGINAL_EFFORT") ""))))

(ert-deftest my/lifeos-scaffold-task-refuses-aggregate ()
  (my/lifeos-test-with-org
      "* TODO Parent
** TODO Child
"
    (should-error (my/lifeos-scaffold-task) :type 'user-error)))

(ert-deftest my/lifeos-scaffold-project-creates-identity-and-empty-properties ()
  (my/lifeos-test-with-org
      "* TODO Define this explicitly\n"
    (let ((file (make-temp-file "lifeos-project-scaffold-")))
      (unwind-protect
          (let ((buffer-file-name file))
            (let ((id (my/lifeos-scaffold-project)))
              (should (stringp id))
              (should (equal (org-entry-get nil "ID") id))
              (should (equal (org-get-heading t t t t)
                             "Define this explicitly #project"))
              (dolist (property '("PROJECT_EFFORT" "DEFAULT_WORK_MODE"
                                  "PLANNING_CHUNK" "ESTIMATE_CONFIDENCE"))
                (should (equal (org-entry-get nil property) "")))))
        (delete-file file)))))

(ert-deftest my/lifeos-scaffold-project-preserves-values-and-rejects-tasks ()
  (my/lifeos-test-with-org
      "* TODO Existing #project\n:PROPERTIES:\n:ID: project-id\n:PROJECT_EFFORT: 2:00\n:END:\n"
    (should (equal (my/lifeos-scaffold-project) "project-id"))
    (should (equal (org-entry-get nil "PROJECT_EFFORT") "2:00")))
  (my/lifeos-test-with-org "* TODO Leaf #task\n"
    (should-error (my/lifeos-scaffold-project) :type 'user-error)))

(ert-deftest my/lifeos-groom-project-prompts-without-requiring-property-knowledge ()
  (my/lifeos-test-with-org
      "* TODO Ship outcome\n"
    (let ((file (make-temp-file "lifeos-project-groom-"))
          (durations '("12:00" "2:00"))
          (choices '("Deep" "Medium")))
      (unwind-protect
          (let ((buffer-file-name file))
            (cl-letf (((symbol-function 'org-read-date)
                       (lambda (&rest _) "2026-11-01"))
                      ((symbol-function 'read-string)
                       (lambda (&rest _) (pop durations)))
                      ((symbol-function 'my/lifeos--read-property)
                       (lambda (&rest _) (pop choices))))
              (should (stringp (my/lifeos-groom-project)))
              (should (string-match-p "2026-11-01"
                                      (org-entry-get nil "DEADLINE")))
              (should (equal (org-entry-get nil "PROJECT_EFFORT") "12:00"))
              (should (equal (org-entry-get nil "DEFAULT_WORK_MODE") "Deep"))
              (should (equal (org-entry-get nil "PLANNING_CHUNK") "2:00"))
              (should (equal (org-entry-get nil "ESTIMATE_CONFIDENCE") "Medium"))))
        (delete-file file)))))

(ert-deftest my/lifeos-auto-scaffold-buffer-scaffolds-explicit-projects ()
  (my/lifeos-test-with-org
      "* TODO Explicit #project\n"
    (let ((file (make-temp-file "lifeos-project-auto-scaffold-")))
      (unwind-protect
          (let ((buffer-file-name file))
            (my/lifeos-auto-scaffold-buffer)
            (should (org-entry-get nil "ID"))
            (should (equal (org-entry-get nil "PROJECT_EFFORT") "")))
        (delete-file file)))))

(ert-deftest my/lifeos-auto-scaffold-buffer-scaffolds-tagged-leaves ()
  (my/lifeos-test-with-org
      "* TODO Captured #task\n"
    (let ((file (make-temp-file "lifeos-auto-scaffold-")))
      (unwind-protect
          (let ((buffer-file-name file))
            (my/lifeos-auto-scaffold-buffer)
            (should (org-entry-get nil "ID"))
            (dolist (property '("EFFORT" "ORIGINAL_EFFORT" "IMPACT"
                                "WORK_MODE"))
              (should (equal (org-entry-get nil property) ""))))
        (delete-file file)))))

(ert-deftest my/lifeos-auto-scaffold-buffer-leaves-aggregate-invalid ()
  (my/lifeos-test-with-org
      "* TODO Parent #task\n** TODO Child\n"
    (my/lifeos-auto-scaffold-buffer)
    (should-not (org-entry-get nil "ID"))))

(ert-deftest my/lifeos-break-down-task-preserves-leaf-and-chains-new-tasks ()
  (my/lifeos-test-with-org
      "* Project #project\n** TODO [#A] Draft and revise #task\n:PROPERTIES:\n:ID: original-id\n:EFFORT: 4:00\n:ORIGINAL_EFFORT: 4:00\n:IMPACT: High\n:WORK_MODE: Deep\n:END:\nDepends on [[depends-on:outline-id][Outline]].\n"
    (let ((file (make-temp-file "lifeos-breakdown-"))
          (ids '("revision-id")))
      (unwind-protect
          (let ((buffer-file-name file)
                (org-agenda-files nil))
            (cl-letf (((symbol-function 'org-id-new)
                       (lambda (&rest _) (pop ids)))
                      ((symbol-function 'org-id-update-id-locations)
                       (lambda (&rest _) nil)))
              (search-forward "Draft and revise")
              (beginning-of-line)
              (let ((result (my/lifeos-break-down-task
                             "Draft and revise essay" "Draft essay"
                             '("Revise and finalize essay") t nil)))
                (should (= (length (plist-get result :leaves)) 2))
                (goto-char (point-min))
                (should (re-search-forward
                         "^\\*\\* Draft and revise essay$" nil t))
                (should (re-search-forward
                         "^\\*\\*\\* TODO \\[#[A]\\] Draft essay #task$" nil t))
                (should (equal (org-entry-get nil "ID") "original-id"))
                (should (re-search-forward
                         "depends-on:outline-id" nil t))
                (should (re-search-forward
                         "^\\*\\*\\* TODO Revise and finalize essay #task$" nil t))
                (should (equal (org-entry-get nil "ID") "revision-id"))
                (should (re-search-forward
                         "depends-on:original-id" nil t)))))
        (delete-file file)))))

(ert-deftest my/lifeos-break-down-task-rewires-downstream-to-terminal-leaf ()
  (my/lifeos-test-with-org
      "* TODO Original #task\n:PROPERTIES:\n:ID: original-id\n:END:\n* TODO Downstream #task\n:PROPERTIES:\n:ID: downstream-id\n:END:\nDepends on [[depends-on:original-id][Original]].\n"
    (let ((file (make-temp-file "lifeos-rewire-"))
          (org-agenda-files nil))
      (unwind-protect
          (let ((buffer-file-name file))
            (setq org-agenda-files (list file))
            (cl-letf (((symbol-function 'org-id-new)
                       (lambda (&rest _) "terminal-id"))
                      ((symbol-function 'org-id-update-id-locations)
                       (lambda (&rest _) nil)))
              (let ((result (my/lifeos-break-down-task
                             "Original work" "First part" '("Last part")
                             nil t)))
                (should (= (plist-get result :rewired) 1))
                (goto-char (point-min))
                (should (re-search-forward
                         "depends-on:terminal-id" nil t))
                (should-not (re-search-forward
                             "depends-on:original-id" nil t)))))
        (delete-file file)))))

(ert-deftest my/lifeos-diagnostics-show-all-reasons-transiently ()
  (my/lifeos-test-with-org
      "* TODO Needs work
"
    (let ((file (make-temp-file "lifeos-diagnostics-")))
      (unwind-protect
          (let ((buffer-file-name file))
            (let ((diagnostics (my/lifeos-task-diagnostics)))
              (my/lifeos-refresh-buffer-diagnostics)
              (should (= (length my/lifeos-diagnostic-overlays) 1))
              (should (= (overlay-start (car my/lifeos-diagnostic-overlays))
                          (point-min)))
              (should (equal (substring-no-properties
                              (overlay-get (car my/lifeos-diagnostic-overlays)
                                           'before-string))
                              " [ERROR 6] "))
              (should (equal (overlay-get (car my/lifeos-diagnostic-overlays)
                                           'lifeos-diagnostics)
                             diagnostics))
              (should (string-match-p
                       "\\[ERROR missing-task-tag\\] Missing #task"
                       (overlay-get (car my/lifeos-diagnostic-overlays)
                                    'help-echo)))))
        (delete-file file)))))

(ert-deftest my/lifeos-diagnostic-labels-group-and-order-severities ()
  (let ((diagnostics
         (list (my/lifeos--diagnostic 'late 'conflict "Late")
               (my/lifeos--diagnostic 'missing-id 'error "Missing ID")
               (my/lifeos--diagnostic 'estimate 'review "Review estimate")
                (my/lifeos--diagnostic 'missing-task-tag 'error "Bad task"))))
    (should (equal (substring-no-properties
                    (my/lifeos--diagnostic-label-string diagnostics))
                   " [ERROR 2] [REVIEW 1] [CONFLICT 1] "))))

(ert-deftest my/lifeos-task-explanation-groups-codes-and-remediation ()
  (let* ((diagnostics
          (list (my/lifeos--diagnostic 'missing-id 'error "Missing ID")
                (my/lifeos--diagnostic 'estimate-exhausted 'review
                                       "Estimate exhausted")))
         (text (my/lifeos--format-task-explanation "Write essay" diagnostics)))
    (should (string-match-p "ERROR" text))
    (should (string-match-p "missing-id" text))
    (should (string-match-p "my/lifeos-scaffold-task" text))
    (should (string-match-p "REVIEW" text))
    (should (string-match-p "my/lifeos-set-remaining-effort" text))))

(ert-deftest my/lifeos-task-explanation-includes-cached-forecast-conflicts ()
  (my/lifeos-test-with-org
      "* TODO [#A] Write essay #task\n:PROPERTIES:\n:ID: essay-id\n:EFFORT: 1:00\n:ORIGINAL_EFFORT: 1:00\n:IMPACT: High\n:WORK_MODE: Deep\n:END:\n"
    (let ((diagnostics (make-hash-table :test #'equal))
          (my/lifeos-project-analysis-cache nil))
      (puthash "essay-id"
               (list (my/lifeos--diagnostic
                      'no-window-before-deadline 'conflict
                      "No compatible window ends before the deadline"))
               diagnostics)
      (setq my/lifeos-project-analysis-cache
            (list :task-diagnostics diagnostics))
      (let ((text (my/lifeos--format-task-explanation
                   "Write essay" (my/lifeos--task-diagnostics-at-point))))
        (should (string-match-p "CONFLICT" text))
        (should (string-match-p "no-window-before-deadline" text))))))

(ert-deftest my/lifeos-diagnostic-navigation-cycles-both-directions ()
  (my/lifeos-test-with-org
      "* DONE Start here
* TODO First
* DONE Fine
* TODO Second
"
    (let ((file (make-temp-file "lifeos-navigation-")))
      (unwind-protect
          (let ((buffer-file-name file))
            (my/lifeos-refresh-buffer-diagnostics)
            (goto-char (point-min))
            (my/lifeos-next-diagnostic)
            (should (looking-at-p "\\* TODO First"))
            (my/lifeos-next-diagnostic)
            (should (looking-at-p "\\* TODO Second"))
            (my/lifeos-next-diagnostic)
            (should (looking-at-p "\\* TODO First"))
            (my/lifeos-previous-diagnostic)
            (should (looking-at-p "\\* TODO Second"))
            (my/lifeos-previous-diagnostic)
            (should (looking-at-p "\\* TODO First")))
        (delete-file file)))))

(ert-deftest my/lifeos-diagnostic-navigation-requires-diagnostics ()
  (my/lifeos-test-with-org
      "* DONE Clean
"
    (should-error (my/lifeos--goto-diagnostic t) :type 'user-error)))

(ert-deftest my/lifeos-diagnostic-navigation-skips-project-summaries ()
  (my/lifeos-test-with-org
      "* Project #project\n* TODO Broken\n"
    (let ((project (my/lifeos--make-diagnostic-overlay
                    " [DONE 0/0] " "Healthy project" nil 'project)))
      (forward-line 1)
      (let ((task (my/lifeos--make-diagnostic-overlay
                   " [ERROR 1] " "Broken task"
                   (list (my/lifeos--diagnostic 'missing-task-tag 'error
                                                "Missing #task"))
                   'task)))
        (should (equal (my/lifeos--diagnostic-overlay-positions)
                       (list (overlay-start task))))
        (delete-overlay task))
      (delete-overlay project))))

(ert-deftest my/lifeos-estimate-balance-uses-only-direct-clocks ()
  (my/lifeos-test-with-org
      "* TODO [#A] Parent #task
:PROPERTIES:
:ID: parent-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:30] =>  0:30
:END:
** TODO Child
:LOGBOOK:
CLOCK: [2026-10-12 Mon 10:00]--[2026-10-12 Mon 11:00] =>  1:00
:END:
"
    (should (= (my/lifeos--direct-clocked-minutes) 30))
    (should (= (my/lifeos-task-estimate-balance) 30))))

(ert-deftest my/lifeos-set-remaining-effort-preserves-baseline ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:30] =>  0:30
:END:
"
    (should (equal (my/lifeos-set-remaining-effort 45) "1:15"))
    (should (equal (org-entry-get nil "EFFORT") "1:15"))
    (should (equal (org-entry-get nil "ORIGINAL_EFFORT") "1:00"))
    (should (= (my/lifeos-task-estimate-balance) 45))))

(ert-deftest my/lifeos-set-remaining-effort-appends-an-idempotent-anchor ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:30] =>  0:30
:END:
"
    (let ((effective (format-time-string
                      "%Y-%m-%dT%H:%M:00Z"
                      (org-time-string-to-time "2026-10-12 Mon 09:30") t)))
      (should (equal (my/lifeos-set-remaining-effort 45 effective) "1:15"))
      (let* ((state (my/lifeos-effort-state))
             (episode (plist-get state :episode-id))
             (correction (car (plist-get state :corrections))))
        (should (plist-get state :valid-p))
        (should (eq (plist-get state :effort-provenance) 'legacy-rewritten))
        (should (plist-get state :correction-anchored-p))
        (should (= (length (plist-get state :episodes)) 1))
        (should (= (length (plist-get state :corrections)) 1))
        (should (= (length (plist-get state :clocks)) 1))
        (should (equal (plist-get (car (plist-get state :clocks)) :episode-id)
                       episode))
        (should (equal (plist-get correction :effective-at) effective))
        (should (= (plist-get correction :remaining-minutes) 45))
        (should (equal (plist-get correction :correction-id)
                       (my/lifeos--effort-correction-id
                        "leaf-id" episode effective 45)))
        (should (equal (plist-get correction :revision)
                       (my/lifeos--effort-correction-revision
                        "leaf-id" episode effective 45))))
      (should (equal (my/lifeos-set-remaining-effort 45 effective) "1:15"))
      (should (= (length (plist-get (my/lifeos-effort-state) :corrections)) 1))
      (should-error (my/lifeos-set-remaining-effort 30 effective)
                    :type 'user-error)
      (should (= (length (plist-get (my/lifeos-effort-state) :corrections)) 1)))))

(ert-deftest my/lifeos-effort-anchor-survives-file-reload ()
  (let* ((file (make-temp-file "lifeos-effort-" nil ".org"))
         (effective (format-time-string
                     "%Y-%m-%dT%H:%M:00Z"
                     (org-time-string-to-time "2026-10-12 Mon 09:30") t))
         (org-todo-keywords
          '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "SOMEDAY(s)"
                      "|" "DONE(d)" "CANCELLED(c)"))))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:END:
"))
          (let ((buffer (find-file-noselect file)))
            (unwind-protect
                (with-current-buffer buffer
                  (org-mode)
                  (goto-char (point-min))
                  (my/lifeos-set-remaining-effort 45 effective)
                  (save-buffer))
              (kill-buffer buffer)))
          (let ((buffer (find-file-noselect file)))
            (unwind-protect
                (with-current-buffer buffer
                  (org-mode)
                  (goto-char (point-min))
                  (let* ((state (my/lifeos-effort-state))
                         (correction (car (plist-get state :corrections))))
                    (should (plist-get state :valid-p))
                    (should (= (length (plist-get state :corrections)) 1))
                    (should (equal (plist-get correction :effective-at)
                                   effective))
                    (should (= (plist-get correction :remaining-minutes) 45))))
              (kill-buffer buffer))))
      (delete-file file))))

(ert-deftest my/lifeos-effort-corrections-are-appended-not-rewritten ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:30] =>  0:30
:END:
"
    (let ((first (format-time-string
                  "%Y-%m-%dT%H:%M:00Z"
                  (org-time-string-to-time "2026-10-12 Mon 10:30") t))
          (second (format-time-string
                   "%Y-%m-%dT%H:%M:00Z"
                   (org-time-string-to-time "2026-10-12 Mon 11:00") t)))
      (my/lifeos-set-remaining-effort 45 first)
      (let ((lines (my/lifeos--effort-record-lines)))
        (my/lifeos-set-remaining-effort 30 second)
        (let* ((after (my/lifeos--effort-record-lines))
               (state (my/lifeos-effort-state)))
          (should (equal lines (seq-take after (length lines))))
          (should (= (length after) (1+ (length lines))))
          (should (= (length (plist-get state :corrections)) 2))
          (should (equal (plist-get (car (plist-get state :corrections))
                                    :effective-at)
                         first)))))))

(ert-deftest my/lifeos-effort-state-keeps-rewritten-effort-unanchored ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:15
:ORIGINAL_EFFORT: 1:00
:END:
"
    (let ((state (my/lifeos-effort-state)))
      (should (plist-get state :valid-p))
      (should (eq (plist-get state :effort-provenance) 'legacy-rewritten))
      (should-not (plist-get state :correction-anchored-p))
      (should-not (plist-get state :episode-id))))
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:END:
"
    ;; Without ORIGINAL_EFFORT, an initial baseline is not provable.
    (should (eq (plist-get (my/lifeos-effort-state) :effort-provenance)
                'legacy-rewritten))))

(ert-deftest my/lifeos-effort-state-treats-empty-properties-as-missing ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT:
:ORIGINAL_EFFORT:
:END:
"
    (let ((state (my/lifeos-effort-state)))
      (should (plist-get state :valid-p))
      (should (eq (plist-get state :effort-provenance) 'missing))
      (should-not (plist-get state :effort-minutes))
      (should-not (plist-get state :issues))))
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 0:00
:ORIGINAL_EFFORT: 0:00
:END:
"
    (let* ((state (my/lifeos-effort-state))
           (codes (mapcar (lambda (issue) (plist-get issue :code))
                          (plist-get state :issues))))
      (should-not (plist-get state :valid-p))
      (should (memq 'nonpositive-effort codes)))))

(ert-deftest my/lifeos-effort-state-rejects-corrupt-corrections ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:END:
:LIFEOS_EFFORT:
EPISODE id=e-1 task=leaf-id start=2026-10-12T09:00:00Z
CORRECTION id=c-1 task=leaf-id episode=e-1 effective=2026-10-12T10:00:00Z remaining=45 revision=wrong
CORRECTION id=c-2 task=leaf-id episode=e-1 effective=2026-10-12T10:00:00Z remaining=30 revision=also-wrong
:END:
"
    (let* ((state (my/lifeos-effort-state))
           (codes (mapcar (lambda (issue) (plist-get issue :code))
                          (plist-get state :issues))))
      (should-not (plist-get state :valid-p))
      (should (memq 'correction-revision-mismatch codes))
      (should (memq 'conflicting-correction-effective codes)))
    (should-error (my/lifeos-set-remaining-effort 20 "2026-10-12T11:00:00Z")
                  :type 'user-error)))

(ert-deftest my/lifeos-effort-state-rejects-a-copied-effort-drawer ()
  (let* ((effective "2026-10-12T10:00:00Z")
         (revision (my/lifeos--effort-correction-revision
                    "other-id" "e-1" effective 45)))
    (my/lifeos-test-with-org
        (format "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:END:
:LIFEOS_EFFORT:
EPISODE id=e-1 task=other-id start=2026-10-12T09:00:00Z
CORRECTION id=c-1 task=other-id episode=e-1 effective=%s remaining=45 revision=%s
:END:
" effective revision)
      (let* ((state (my/lifeos-effort-state))
             (codes (mapcar (lambda (issue) (plist-get issue :code))
                            (plist-get state :issues))))
        (should-not (plist-get state :valid-p))
        (should (memq 'episode-task-mismatch codes))
        (should (memq 'correction-task-mismatch codes))))))

(ert-deftest my/lifeos-effort-state-rejects-an-unclosed-drawer ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:END:
:LIFEOS_EFFORT:
EPISODE id=e-1 task=leaf-id start=2026-10-12T09:00:00Z
"
    (let* ((state (my/lifeos-effort-state))
           (codes (mapcar (lambda (issue) (plist-get issue :code))
                          (plist-get state :issues))))
      (should-not (plist-get state :valid-p))
      (should (memq 'unclosed-effort-drawer codes)))
    (should-error (my/lifeos-set-remaining-effort 30 "2026-10-12T10:00:00Z")
                  :type 'user-error)))

(ert-deftest my/lifeos-effort-state-attributes-clocks-to-episodes ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:END:
:LIFEOS_EFFORT:
EPISODE id=e-1 task=leaf-id start=2000-01-01T00:00:00Z
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:30] =>  0:30
:END:
"
    (let ((state (my/lifeos-effort-state)))
      (should (plist-get state :valid-p))
      (should (eq (plist-get state :clock-zone-basis) 'machine-local))
      (should (equal (plist-get (car (plist-get state :clocks)) :episode-id)
                     "e-1"))))
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:END:
:LIFEOS_EFFORT:
EPISODE id=e-1 task=leaf-id start=2030-01-01T00:00:00Z
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:30] =>  0:30
:END:
"
    (let* ((state (my/lifeos-effort-state))
           (codes (mapcar (lambda (issue) (plist-get issue :code))
                          (plist-get state :issues))))
      (should-not (plist-get state :valid-p))
      (should (memq 'clock-before-episode codes))
      (should-not (plist-get state :clocks))))
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:END:
:LIFEOS_EFFORT:
EPISODE id=e-1 task=leaf-id start=2000-01-01T00:00:00Z
EPISODE id=e-2 task=leaf-id start=2030-01-01T00:00:00Z
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]
:END:
"
    (let* ((state (my/lifeos-effort-state))
           (codes (mapcar (lambda (issue) (plist-get issue :code))
                          (plist-get state :issues))))
      (should (memq 'clock-crosses-episode codes))
      (should-not (plist-get state :clocks)))))

(ert-deftest my/lifeos-exhausted-estimate-is-review-not-error ()
  (my/lifeos-test-with-org
      "* TODO [#A] Leaf #task
:PROPERTIES:
:ID: leaf-id
:EFFORT: 0:30
:ORIGINAL_EFFORT: 0:30
:IMPACT: High
:WORK_MODE: Deep
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:45] =>  0:45
:END:
"
    (let ((diagnostic
           (seq-find (lambda (item)
                       (eq (plist-get item :code) 'estimate-exhausted))
                     (my/lifeos-task-diagnostics))))
      (should diagnostic)
      (should (eq (plist-get diagnostic :severity) 'review))
      (should (my/lifeos-task-eligible-p '("TODO" "NEXT")))
      (should-not (my/lifeos-task-forecast-minutes)))))

(ert-deftest my/lifeos-review-only-task-record-remains-eligible ()
  (my/lifeos-test-with-agenda-file
      "* TODO [#A] Leaf #task\n:PROPERTIES:\n:ID: leaf-id\n:EFFORT: 0:30\n:ORIGINAL_EFFORT: 0:30\n:IMPACT: High\n:WORK_MODE: Deep\n:END:\n:LOGBOOK:\nCLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:45] =>  0:45\n:END:\n"
    (cl-letf (((symbol-function 'org-id-update-id-locations)
               (lambda (&rest _) nil)))
      (let ((record (car (my/lifeos--task-records))))
        (should (plist-get record :eligible))
        (should (= (plist-get record :balance) -15))
        (should-not (plist-get record :minutes))))))

(ert-deftest my/lifeos-graph-reports-invalid-prerequisite ()
  (cl-letf (((symbol-function 'my/lifeos--task-records)
             (lambda ()
               '((:id "dependent" :state "TODO" :eligible t
                  :targets ("invalid"))
                 (:id "invalid" :state "TODO" :eligible nil
                  :targets nil :diagnostics ((:code non-leaf-task)))))))
    (let ((analysis (my/lifeos-graph-analysis)))
      (should (equal (plist-get analysis :invalid-targets)
                     '(("dependent" . "invalid"))))
      (should-not (plist-get analysis :order)))))

(ert-deftest my/lifeos-graph-reports-inactive-prerequisite ()
  (cl-letf (((symbol-function 'my/lifeos--task-records)
             (lambda ()
               '((:id "dependent" :state "TODO" :eligible t
                  :targets ("someday"))
                 (:id "someday" :state "SOMEDAY" :eligible t
                  :targets nil)))))
    (let ((analysis (my/lifeos-graph-analysis)))
      (should (equal (plist-get analysis :inactive-targets)
                     '(("dependent" . "someday"))))
      (should-not (plist-get analysis :order)))))

(ert-deftest my/lifeos-task-id-eligibility-rejects-aggregate ()
  (my/lifeos-test-with-org
      "* TODO [#A] Parent #task
:PROPERTIES:
:ID: parent-id
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
** TODO Child
"
    (let ((marker (copy-marker (point))))
      (cl-letf (((symbol-function 'org-id-find)
                 (lambda (&rest _) marker)))
        (should-not
         (my/lifeos--task-id-eligible-p "parent-id" '("TODO" "NEXT")))))))

(ert-deftest my/lifeos-unrelated-invalid-task-does-not-block-valid-graph ()
  (cl-letf (((symbol-function 'my/lifeos--task-records)
             (lambda ()
               '((:id "valid" :state "TODO" :eligible t :targets nil)
                 (:id "invalid" :state "TODO" :eligible nil
                  :targets nil :diagnostics ((:code non-leaf-task)))))))
    (let ((analysis (my/lifeos-graph-analysis)))
      (should (equal (mapcar (lambda (record) (plist-get record :id))
                             (plist-get analysis :records))
                     '("valid")))
      (should (equal (plist-get analysis :order) '("valid"))))))

(ert-deftest my/lifeos-empty-graph-is-valid ()
  (cl-letf (((symbol-function 'my/lifeos--task-records) (lambda () nil))
            ((symbol-function 'my/lifeos--project-records) (lambda () nil))
            ((symbol-function 'org-id-update-id-locations) (lambda (&rest _) nil)))
    (let ((analysis (my/lifeos-graph-analysis)))
      (should (plist-get analysis :valid-p))
      (should-not (plist-get analysis :order)))))

(ert-deftest my/lifeos-analysis-inventories-only-explicit-projects-and-orphans ()
  (my/lifeos-test-with-agenda-file
      "#+TODO: TODO NEXT WAITING SOMEDAY | DONE CANCELLED
* Active project #project
DEADLINE: <2026-11-01 Sun>
:PROPERTIES:
:ID: active-project
:PROJECT_EFFORT: 1:00
:END:
** TODO [#A] Project task #task
:PROPERTIES:
:ID: project-task
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
* SOMEDAY Later project #project
DEADLINE: <2026-12-01 Tue>
:PROPERTIES:
:ID: later-project
:PROJECT_EFFORT: 1:00
:END:
* Candidate container
** TODO Unclassified work
* TODO [#A] Orphan task #task
:PROPERTIES:
:ID: orphan-task
:EFFORT: 0:30
:ORIGINAL_EFFORT: 0:30
:IMPACT: High
:WORK_MODE: Errand
:END:
"
    (cl-letf (((symbol-function 'org-id-update-id-locations)
               (lambda (&rest _) nil)))
      (let* ((analysis (my/lifeos-graph-analysis))
             (projects (plist-get analysis :projects))
             (active (seq-find (lambda (record)
                                 (equal (plist-get record :id) "active-project"))
                               projects))
             (later (seq-find (lambda (record)
                                (equal (plist-get record :id) "later-project"))
                              projects))
              (orphan (car (plist-get analysis :orphan-records))))
        (should (= (length projects) 2))
        (should (eq (plist-get active :commitment) 'committed))
        (should (eq (plist-get later :commitment) 'uncommitted))
        (should (marker-position (plist-get active :marker)))
        (should (equal (plist-get orphan :id) "orphan-task"))
        (should (marker-position (plist-get orphan :marker)))))))

(ert-deftest my/lifeos-project-definition-reports-required-and-coarse-metadata ()
  (my/lifeos-test-with-agenda-file
      "* Active project #project
:PROPERTIES:
:PROJECT_EFFORT: 2:00
:DEFAULT_WORK_MODE: Focused
:PLANNING_CHUNK: 0:10
:ESTIMATE_CONFIDENCE: Certain
:END:
* Invalid effort #project
DEADLINE: <2026-11-01 Sun>
:PROPERTIES:
:ID: invalid-effort
:PROJECT_EFFORT: 1:10
:END:
"
    (cl-letf (((symbol-function 'org-id-update-id-locations)
               (lambda (&rest _) nil)))
      (let* ((projects (plist-get (my/lifeos-graph-analysis) :projects))
             (project (car projects))
             (invalid-effort (cadr projects))
             (codes (mapcar (lambda (diagnostic)
                              (plist-get diagnostic :code))
                            (plist-get project :diagnostics))))
        (should (eq (plist-get project :definition-status) 'incomplete))
        (dolist (code '(missing-project-id invalid-project-deadline
                        invalid-default-work-mode invalid-planning-chunk
                        invalid-estimate-confidence))
          (should (memq code codes)))
        (should (eq (plist-get invalid-effort :definition-status) 'incomplete))
        (should (seq-find
                 (lambda (diagnostic)
                   (eq (plist-get diagnostic :code) 'invalid-project-effort))
                 (plist-get invalid-effort :diagnostics)))))))

(ert-deftest my/lifeos-project-definition-distinguishes-coarse-detailed-and-unresolved ()
  (my/lifeos-test-with-agenda-file
      "* Coarse #project
DEADLINE: <2026-11-01 Sun>
:PROPERTIES:
:ID: coarse
:PROJECT_EFFORT: 2:00
:DEFAULT_WORK_MODE: Deep
:PLANNING_CHUNK: 1:00
:ESTIMATE_CONFIDENCE: Medium
:END:
* Detailed #project
DEADLINE: <2026-11-01 Sun>
:PROPERTIES:
:ID: detailed
:PROJECT_EFFORT: 1:00
:END:
** TODO [#A] Defined task #task
:PROPERTIES:
:ID: defined-task
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
* Unresolved #project
DEADLINE: <2026-11-01 Sun>
:PROPERTIES:
:ID: unresolved
:PROJECT_EFFORT: 1:00
:DEFAULT_WORK_MODE: Deep
:PLANNING_CHUNK: 1:00
:ESTIMATE_CONFIDENCE: Low
:END:
** TODO Needs definition
"
    (cl-letf (((symbol-function 'org-id-update-id-locations)
               (lambda (&rest _) nil)))
      (let* ((projects (plist-get (my/lifeos-graph-analysis) :projects))
             (status (lambda (id)
                       (plist-get
                        (seq-find (lambda (project)
                                    (equal (plist-get project :id) id))
                                  projects)
                        :definition-status))))
        (should (eq (funcall status "coarse") 'coarse))
        (should (eq (funcall status "detailed") 'detailed))
        (should (eq (funcall status "unresolved") 'incomplete))
        (let ((unresolved
               (seq-find (lambda (project)
                           (equal (plist-get project :id) "unresolved"))
                         projects)))
          (should (marker-position
                   (plist-get (car (plist-get unresolved
                                              :unresolved-descendants))
                              :marker)))
          (should (seq-find
                   (lambda (diagnostic)
                     (eq (plist-get diagnostic :code)
                         'unresolved-descendant-work))
                   (plist-get unresolved :diagnostics))))))))

(ert-deftest my/lifeos-project-effort-envelope-accounts-for-completed-and-overallocated-work ()
  (my/lifeos-test-with-agenda-file
      "* Partial #project
DEADLINE: <2026-11-01 Sun>
:PROPERTIES:
:ID: partial
:PROJECT_EFFORT: 2:00
:DEFAULT_WORK_MODE: Deep
:PLANNING_CHUNK: 0:30
:ESTIMATE_CONFIDENCE: High
:END:
** TODO [#A] Active #task
:PROPERTIES:
:ID: active
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
:LOGBOOK:
CLOCK: [2026-10-12 Mon 09:00]--[2026-10-12 Mon 09:15] =>  0:15
:END:
** DONE Completed #task
:PROPERTIES:
:ID: completed
:EFFORT: 0:30
:ORIGINAL_EFFORT: 0:30
:IMPACT: High
:WORK_MODE: Deep
:END:
* Overallocated #project
DEADLINE: <2026-11-01 Sun>
:PROPERTIES:
:ID: overallocated
:PROJECT_EFFORT: 0:30
:END:
** TODO [#A] Too much #task
:PROPERTIES:
:ID: too-much
:EFFORT: 1:00
:ORIGINAL_EFFORT: 1:00
:IMPACT: High
:WORK_MODE: Deep
:END:
"
    (cl-letf (((symbol-function 'org-id-update-id-locations)
               (lambda (&rest _) nil)))
      (let* ((projects (plist-get (my/lifeos-graph-analysis) :projects))
             (partial (seq-find (lambda (project)
                                  (equal (plist-get project :id) "partial"))
                                projects))
             (overallocated
              (seq-find (lambda (project)
                          (equal (plist-get project :id) "overallocated"))
                        projects)))
        (should (= (plist-get partial :explicit-effort-minutes) 90))
        (should (= (plist-get partial :explicit-remaining-minutes) 45))
        (should (= (plist-get partial :unallocated-effort-minutes) 30))
        (should (= (plist-get partial :remaining-effort-minutes) 75))
        (should (eq (plist-get partial :definition-status) 'coarse))
        (should (= (plist-get overallocated :explicit-effort-minutes) 60))
        (should (= (plist-get overallocated :explicit-remaining-minutes) 60))
        (should (= (plist-get overallocated :unallocated-effort-minutes) 0))
        (should (= (plist-get overallocated :remaining-effort-minutes) 60))
        (should (eq (plist-get overallocated :definition-status) 'incomplete))
        (should (seq-find
                 (lambda (diagnostic)
                   (eq (plist-get diagnostic :code)
                       'project-effort-overallocated))
                 (plist-get overallocated :diagnostics)))))))

(ert-deftest my/lifeos-project-summary-aggregates-progress-and-coverage ()
  (let* ((project '(:key "project" :title "Essay" :deadline "<2026-10-20 Tue>"))
         (records
          '((:id "done" :title "Done" :state "DONE" :project-key "project"
             :eligible t :executable t :balance 0)
            (:id "fixed" :title "Fixed" :state "TODO" :project-key "project"
             :eligible t :executable t :balance 60 :minutes 60 :scheduled t)
            (:id "planned" :title "Planned" :state "NEXT" :project-key "project"
             :eligible t :executable t :balance 90 :minutes 90)
            (:id "unknown" :title "Unknown" :state "TODO" :project-key "project"
             :eligible nil :executable t :balance nil :minutes nil)))
         (analysis (list :projects (list project) :all-records records
                         :records (seq-filter (lambda (record)
                                                (plist-get record :eligible))
                                              records)
                         :valid-p t :missing-targets nil :inactive-targets nil
                         :invalid-targets nil :cycles nil))
         (forecast
          '(:placements ((:id "fixed" :project-key "project" :kind fixed
                          :start (0 0 0 0) :end (0 100 0 0))
                         (:id "planned" :project-key "project" :kind proposed
                          :start (0 100 0 0) :end (0 200 0 0)))
            :failures nil))
         (summary (gethash "project"
                           (my/lifeos--project-summaries analysis forecast))))
    (should (= (plist-get summary :done-count) 1))
    (should (= (plist-get summary :total-count) 4))
    (should (= (plist-get summary :left-minutes) 150))
    (should (= (length (plist-get summary :unknown-records)) 1))
    (should (= (plist-get summary :fixed-count) 1))
    (should (= (plist-get summary :planned-count) 2))
    (should (= (plist-get summary :active-count) 2))
    (should (eq (plist-get summary :tightness) 'unknown))))

(ert-deftest my/lifeos-project-summary-left-excludes-active-aggregate-tasks ()
  (let* ((analysis
          '(:projects ((:key "project" :title "Essay"))
            :all-records ((:id "aggregate" :title "Aggregate" :state "TODO"
                           :project-key "project" :eligible nil :executable nil
                           :balance 120 :minutes 120)
                          (:id "leaf" :title "Leaf" :state "TODO"
                           :project-key "project" :eligible t :executable t
                           :balance 30 :minutes 30))
            :records ((:id "leaf" :title "Leaf" :state "TODO"
                       :project-key "project" :eligible t :executable t
                       :balance 30 :minutes 30))
            :valid-p t :missing-targets nil :inactive-targets nil
            :invalid-targets nil :cycles nil))
         (forecast '(:placements nil :failures nil))
         (summary (gethash "project"
                           (my/lifeos--project-summaries analysis forecast))))
    (should (= (plist-get summary :left-minutes) 30))
    (should-not (memq (car (plist-get analysis :all-records))
                      (plist-get summary :unknown-records)))))

(ert-deftest my/lifeos-project-summary-counts-unplaced-and-numeric-tightness ()
  (let* ((deadline (format-time-string "<%Y-%m-%d %a>"
                                       (time-add (current-time) (days-to-time 2))))
         (analysis
          (list :projects (list (list :key "project" :title "Essay"
                                      :deadline deadline))
                :all-records
                '((:id "placed" :title "Placed" :state "TODO"
                   :project-key "project" :eligible t :executable t
                   :balance 60 :minutes 60))
                :records
                '((:id "placed" :title "Placed" :state "TODO"
                   :project-key "project" :eligible t :executable t
                   :balance 60 :minutes 60))
                :valid-p t :missing-targets nil :inactive-targets nil
                :invalid-targets nil :cycles nil))
         (end (time-add (current-time) (days-to-time 1)))
         (forecast (list :placements
                         (list (list :id "placed" :project-key "project"
                                     :kind 'proposed :start (current-time)
                                     :end end))
                         :failures nil))
         (summary (gethash "project"
                           (my/lifeos--project-summaries analysis forecast))))
    (should (numberp (plist-get summary :tightness)))
    (should (= (plist-get summary :planned-count) 1))
    (should (= (plist-get summary :unplaced-count) 0))))

(ert-deftest my/lifeos-project-analysis-invalidation-debounces ()
  (let ((my/lifeos-project-analysis-timer 'old)
        cancelled scheduled)
    (cl-letf (((symbol-function 'timerp) (lambda (_) t))
              ((symbol-function 'cancel-timer)
               (lambda (timer) (push timer cancelled)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (delay _repeat function)
                 (setq scheduled (list delay function))
                 'new)))
      (my/lifeos-invalidate-project-analysis)
      (should (equal cancelled '(old)))
      (should (equal scheduled
                     (list my/lifeos-project-analysis-idle-delay
                           #'my/lifeos-refresh-project-analysis)))
      (should (eq my/lifeos-project-analysis-timer 'new)))))

(ert-deftest my/lifeos-project-diagnostics-are-local-navigable-and-read-only ()
  (my/lifeos-test-with-org
      "* Project #project\n* TODO Broken task\n"
    (let ((before (buffer-string))
          (buffer-file-name (make-temp-file "lifeos-project-diagnostics-"))
          (my/lifeos-project-analysis-cache nil))
      (let* ((project (my/lifeos-project-record-at-point))
             (codes (mapcar (lambda (diagnostic)
                              (plist-get diagnostic :code))
                            (plist-get project :diagnostics))))
        (should (eq (plist-get project :definition-status) 'incomplete))
        (dolist (code '(missing-project-id invalid-project-deadline
                        invalid-project-effort))
          (should (memq code codes))))
      (my/lifeos-refresh-buffer-diagnostics)
      (should (equal before (buffer-string)))
      (should (= (length (my/lifeos--diagnostic-overlay-positions)) 2))
      (goto-char (point-min))
      (my/lifeos-next-diagnostic)
      (should (looking-at-p "\\* TODO Broken task"))
      (my/lifeos-next-diagnostic)
      (should (looking-at-p "\\* Project #project")))))

(ert-deftest my/lifeos-project-explanation-puts-remediation-before-metrics ()
  (my/lifeos-test-with-org "* Project #project\n"
    (let* ((project (my/lifeos-project-record-at-point))
           (diagnostics (plist-get project :diagnostics))
           (text (concat
                  (my/lifeos--format-task-explanation "Project" diagnostics)
                  "\nForecast metrics\n")))
      (should (string-match-p "my/lifeos-groom-project" text))
      (should (< (string-match "missing-project-id" text)
                 (string-match "Forecast metrics" text))))))

(ert-deftest my/lifeos-grooming-record-is-type-aware ()
  (my/lifeos-test-with-org "* Project #project\n"
    (let ((record (my/lifeos--grooming-record)))
      (should (eq (plist-get record :kind) 'project))
      (should-not (seq-find (lambda (diagnostic)
                              (eq (plist-get diagnostic :code)
                                  'missing-task-tag))
                            (plist-get record :diagnostics))))))

(ert-deftest my/lifeos-project-enums-use-standard-org-completion ()
  (should (equal (alist-get "DEFAULT_WORK_MODE_ALL" org-global-properties
                            nil nil #'equal)
                 "Deep Shallow Errand Social"))
  (should (equal (alist-get "ESTIMATE_CONFIDENCE_ALL" org-global-properties
                            nil nil #'equal)
                 "Low Medium High"))
  (should-not (alist-get "PROJECT_EFFORT_ALL" org-global-properties
                         nil nil #'equal))
  (should-not (alist-get "PLANNING_CHUNK_ALL" org-global-properties
                         nil nil #'equal)))

(ert-deftest my/lifeos-forecast-accepts-empty-valid-graph ()
  (let ((analysis (list :records nil :by-id (make-hash-table :test #'equal)
                        :edges nil :valid-p t :order nil)))
    (cl-letf (((symbol-function 'my/lifeos-graph-analysis)
               (lambda () (ert-fail "supplied analysis was ignored")))
              ((symbol-function 'my/lifeos--grooming-records) (lambda (_) nil))
              ((symbol-function 'my/lifeos--forecast-availability)
               (lambda (&rest _) nil))
              ((symbol-function 'my/lifeos--calendar-busy-ranges)
               (lambda (&rest _) nil))
              ((symbol-function 'my/lifeos-critical-paths)
               (lambda (&rest _) nil)))
      (let ((forecast (my/lifeos-build-forecast "2026-10-12" 4 analysis)))
        (should-not (plist-get forecast :failures))
        (should-not (plist-get forecast :placements))))))

(ert-deftest my/lifeos-forecast-preserves-project-identity ()
  (let* ((record '(:id "task" :title "Task" :state "TODO" :minutes 60
                    :balance 60 :work-mode "Deep"
                   :priority "A" :impact "High" :targets nil
                   :project-id "project-id" :project-key "project-key"))
         (by-id (make-hash-table :test #'equal))
         (analysis (list :records (list record) :by-id by-id
                         :edges '(("task")) :valid-p t :order '("task")))
         (start (my/lifeos--date-time "2026-10-12" "09:00"))
         (end (my/lifeos--date-time "2026-10-12" "11:00")))
    (puthash "task" record by-id)
    (should (equal (my/lifeos--forecast-order
                    (list record) '(("task")) nil
                    (my/lifeos--date-time "2026-10-12" "00:00"))
                   '("task")))
    (cl-letf (((symbol-function 'my/lifeos--grooming-records) (lambda (_) nil))
              ((symbol-function 'my/lifeos--forecast-availability)
               (lambda (&rest _) (list (list :start start :end end
                                              :modes '("Deep")))))
              ((symbol-function 'my/lifeos--calendar-busy-ranges)
               (lambda (&rest _) nil))
              ((symbol-function 'my/lifeos-critical-paths)
                (lambda (&rest _) nil))
              ((symbol-function 'my/lifeos--record-scheduled-time)
                (lambda (_) nil))
              ((symbol-function 'my/lifeos-intentions-for-week)
               (lambda (_)
                 '((:name "Degree" :selector (project-id "project-id"))))))
      (let* ((forecast (my/lifeos-build-forecast "2026-10-12" 1 analysis))
             (placement (car (plist-get forecast :placements))))
        (should-not (plist-get forecast :failures))
        (should placement)
        (should (equal (plist-get placement :project-id) "project-id"))
        (should (equal (plist-get placement :project-key) "project-key"))
        (should-not (plist-member placement :domain))
        (should (equal (plist-get placement :intentions) '("Degree")))
        (should (eq (plist-get placement :kind) 'proposed))))))

(ert-deftest my/lifeos-forecast-week-rows-report-intention-pressure ()
  (let ((forecast '(:start "2026-10-12" :weeks 1 :graph analysis)))
    (cl-letf (((symbol-function 'my/lifeos-intention-ledger)
               (lambda (week supplied-forecast supplied-analysis)
                 (should (equal week "2026-10-12"))
                 (should (eq supplied-forecast forecast))
                 (should (eq supplied-analysis 'analysis))
                 '((:name "Degree" :target 240 :actual 30 :fixed 60
                    :proposed 90 :target-remaining 60)))))
      (let ((rows (my/lifeos--forecast-week-rows forecast)))
        (should (= (length rows) 1))
        (should (equal (plist-get (cdar rows) :name) "Degree"))))))

(ert-deftest my/lifeos-forecast-report-renders-intentions-and-unconfigured-state ()
  (let ((forecast '(:data-errors nil :graph (:valid-p t)
                    :placements ((:kind proposed :title "Essay"
                                  :start (27073 48928) :end (27073 52528)
                                  :intentions ("Degree" "Reading") :mode "Deep"))
                    :failures nil)))
    (cl-letf (((symbol-function 'my/lifeos-build-forecast)
               (lambda (&rest _) forecast))
              ((symbol-function 'my/lifeos--forecast-week-rows)
               (lambda (_) nil)))
      (with-temp-buffer
        (org-mode)
        (org-dblock-write:lifeos-forecast '(:start "2026-10-12" :weeks 1))
        (let ((text (buffer-string)))
          (should (string-match-p (regexp-quote "| Intentions") text))
          (should (string-match-p "Degree, Reading" text))
          (should (string-match-p "No allocation targets are configured" text)))))))

(provide 'lifeos-planning-test)
;;; lifeos-planning-test.el ends here
