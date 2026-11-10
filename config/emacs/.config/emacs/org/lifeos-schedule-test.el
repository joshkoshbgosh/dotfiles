;;; lifeos-schedule-test.el --- Tests for adjustable LifeOS schedules -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(let ((directory (file-name-directory (or load-file-name buffer-file-name))))
  (load (expand-file-name "lifeos-planning.el" directory) nil t)
  (load (expand-file-name "lifeos-forecast.el" directory) nil t)
  (load (expand-file-name "lifeos-schedule.el" directory) nil t)
  (load (expand-file-name "lifeos-solver.el" directory) nil t))

(defmacro my/lifeos-schedule-test-with-planning (content &rest body)
  (declare (indent 1) (debug t))
  `(let* ((directory (make-temp-file "lifeos-schedule-" t))
          (org-directory directory)
          (org-agenda-files nil)
          (file (expand-file-name "planning.org" directory))
          (my/lifeos-schedule-active-candidate nil)
          (my/lifeos-schedule-debounce-timer nil)
          (my/lifeos-schedule-restore-token nil))
     (unwind-protect
         (progn
           (write-region ,content nil file nil 'silent)
           ,@body)
       (when (timerp my/lifeos-schedule-debounce-timer)
         (cancel-timer my/lifeos-schedule-debounce-timer))
       (when-let* ((buffer (get-file-buffer file)))
         (set-buffer-modified-p nil)
         (kill-buffer buffer))
       (delete-directory directory t))))

(defun my/lifeos-schedule-test-block (&optional source start role kind)
  (let ((source (or source "task-a"))
        (start (or start 30000000))
        (kind (or kind 'task)))
    (list :id (concat "block-" source) :kind kind
          :task-id (and (eq kind 'task) source)
          :project-id (if (eq kind 'project-capacity) source "project-a")
          :source-id source :title (concat "Work " source) :start start
          :end (+ start 60) :minutes 60 :role (or role 'new))))

(defun my/lifeos-schedule-test-context (&optional start end)
  (list :request-id "portfolio-request"
        :input-fingerprint (my/lifeos-schedule-authoritative-fingerprint)
        :request `((requestId . "portfolio-request")
                   (horizon . ((start . ,(or start 29999900))
                               (end . ,(or end 30010000))))
                   (tasks . []))
        :analysis '(:all-records nil :projects nil)
        :source-markers (make-hash-table :test #'equal)))

(defun my/lifeos-schedule-test-candidate (&optional blocks fixed)
  (let ((candidate
         (my/lifeos-schedule-create
          (my/lifeos-schedule-test-context)
          (or blocks (list (my/lifeos-schedule-test-block))) fixed)))
    (when (timerp my/lifeos-schedule-debounce-timer)
      (cancel-timer my/lifeos-schedule-debounce-timer)
      (setq my/lifeos-schedule-debounce-timer nil))
    candidate))

(defun my/lifeos-schedule-test-response (candidate &rest overrides)
  (append overrides
          (list :candidate-id (my/lifeos-schedule-candidate-id candidate)
                :revision (my/lifeos-schedule-candidate-revision candidate)
                :input-fingerprint
                (my/lifeos-schedule-candidate-input-fingerprint candidate)
                :request-id
                (my/lifeos-schedule-candidate-pending-request-id candidate)
                :complete t :verified t :hard-conflicts nil
                :safety-pass t :reserve-pass t :intention-pass t
                :confidence-pass t :capacity-pass t)))

(defun my/lifeos-schedule-test-make-current (candidate &rest overrides)
  (setf (my/lifeos-schedule-candidate-condition candidate) 'checking
        (my/lifeos-schedule-candidate-pending-request-id candidate) "check-1")
  (should (my/lifeos-schedule-apply-response
           candidate (apply #'my/lifeos-schedule-test-response
                            candidate overrides)))
  candidate)

(ert-deftest my/lifeos-schedule-current-plan-absence-is-valid ()
  (my/lifeos-schedule-test-with-planning "* Policy\n"
    (let ((plan (my/lifeos-schedule-parse-current-plan)))
      (should (plist-get plan :valid-p))
      (should-not (plist-get plan :present-p))
      (should-not (plist-get plan :blocks)))))

(ert-deftest my/lifeos-schedule-plan-round-trips-both-kinds-deterministically ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((task (my/lifeos-schedule-test-block "task-a" 30000060 'keep 'task))
           (capacity (my/lifeos-schedule-test-block
                      "project-z" 30000000 'capacity 'project-capacity))
           (text (my/lifeos-schedule-serialize-plan
                  "plan" "source" 30000000 30001000 29999999
                  (list task capacity))))
      (write-region text nil file nil 'silent)
      (let ((plan (my/lifeos-schedule-parse-current-plan)))
        (should (plist-get plan :valid-p))
        (should (equal (mapcar (lambda (block) (plist-get block :kind))
                               (plist-get plan :blocks))
                       '(project-capacity task)))
        (should (equal text
                       (my/lifeos-schedule-serialize-plan
                        "plan" "source" 30000000 30001000 29999999
                        (list task capacity))))))))

(ert-deftest my/lifeos-schedule-plan-rejects-duplicates-malformation-and-projection-drift ()
  (my/lifeos-schedule-test-with-planning
      "* Accepted schedule\n* Accepted schedule\n"
    (should-not (plist-get (my/lifeos-schedule-parse-current-plan) :valid-p)))
  (my/lifeos-schedule-test-with-planning
      "* Accepted schedule\n:PROPERTIES:\n:LIFEOS_PLAN_ID: p\n:END:\n"
    (should (string-match-p
             "missing LIFEOS_PLAN_SOURCE_FINGERPRINT"
             (car (plist-get (my/lifeos-schedule-parse-current-plan) :issues)))))
  (my/lifeos-schedule-test-with-planning ""
    (let ((text (my/lifeos-schedule-serialize-plan
                 "p" "f" 30000000 30001000 29999999
                 (list (my/lifeos-schedule-test-block)))))
      (setq text (replace-regexp-in-string
                  ":LIFEOS_PLAN_MINUTES: 60"
                  ":LIFEOS_PLAN_MINUTES: 45" text t t))
      (write-region text nil file nil 'silent)
      (should-not (plist-get (my/lifeos-schedule-parse-current-plan) :valid-p))))
  (my/lifeos-schedule-test-with-planning ""
    (let ((text (my/lifeos-schedule-serialize-plan
                 "p" "f" 30000000 30001000 29999999
                 (list (my/lifeos-schedule-test-block)))))
      (setq text (replace-regexp-in-string "<[^>]+>" "<2026-01-01 Thu 09:00-10:00>"
                                           text t t))
      (write-region text nil file nil 'silent)
      (should (string-match-p
               "timestamp does not match"
               (car (plist-get (my/lifeos-schedule-parse-current-plan) :issues)))))))

(ert-deftest my/lifeos-schedule-candidate-lifecycle-is-single-revisioned-and-closable ()
  (my/lifeos-schedule-test-with-planning ""
    (let ((candidate (my/lifeos-schedule-test-candidate)))
      (should (eq (my/lifeos-schedule-candidate-condition candidate) 'checking))
      (should-error (my/lifeos-schedule-test-candidate) :type 'user-error)
      (my/lifeos-schedule-test-make-current candidate)
      (should (eq (my/lifeos-schedule-candidate-condition candidate) 'current))
      (should (my/lifeos-schedule-acceptable-p candidate))
      (my/lifeos-schedule-place candidate "task-a" 30000120)
      (should (= (my/lifeos-schedule-candidate-revision candidate) 1))
      (should (eq (my/lifeos-schedule-candidate-condition candidate) 'editing))
      (should-not (my/lifeos-schedule-acceptable-p candidate))
      (my/lifeos-schedule-mark-stale candidate)
      (should (eq (my/lifeos-schedule-candidate-condition candidate) 'stale))
      (my/lifeos-schedule-close candidate)
      (should (my/lifeos-schedule-candidate-closed candidate))
      (should-not my/lifeos-schedule-active-candidate))))

(ert-deftest my/lifeos-schedule-edits-are-reversible-and-never-write-org ()
  (my/lifeos-schedule-test-with-planning "* Policy\n"
    (let* ((before (with-temp-buffer (insert-file-contents file) (buffer-string)))
           (candidate (my/lifeos-schedule-test-candidate))
           (original (copy-tree (my/lifeos-schedule-candidate-blocks candidate))))
      (my/lifeos-schedule-place candidate "task-a" 30000120)
      (my/lifeos-schedule-reestimate candidate "task-a" 90)
      (my/lifeos-schedule-exclude candidate "task-a")
      (should-not (my/lifeos-schedule-candidate-blocks candidate))
      (should (= (length (my/lifeos-schedule-candidate-exclusions candidate)) 1))
      (my/lifeos-schedule-undo candidate)
      (should (= (plist-get (car (my/lifeos-schedule-candidate-blocks candidate))
                            :minutes) 90))
      (my/lifeos-schedule-undo candidate)
      (my/lifeos-schedule-undo candidate)
      (should (equal (my/lifeos-schedule-candidate-blocks candidate) original))
      (should (= (my/lifeos-schedule-candidate-revision candidate) 6))
      (should (equal before
                     (with-temp-buffer (insert-file-contents file) (buffer-string)))))))

(ert-deftest my/lifeos-schedule-debounce-coalesces-and-response-gates-identity ()
  (my/lifeos-schedule-test-with-planning ""
    (let ((candidate (my/lifeos-schedule-test-candidate)) cancelled scheduled)
      (setq my/lifeos-schedule-debounce-timer 'old)
      (cl-letf (((symbol-function 'timerp) (lambda (_) t))
                ((symbol-function 'cancel-timer)
                 (lambda (timer) (push timer cancelled)))
                ((symbol-function 'run-with-idle-timer)
                 (lambda (delay _repeat function argument)
                   (setq scheduled (list delay function argument))
                   'new)))
        (my/lifeos-schedule-schedule-analysis candidate)
        (my/lifeos-schedule-schedule-analysis candidate)
        (should (equal cancelled '(new old)))
        (should (eq (nth 1 scheduled) #'my/lifeos-schedule--send-analysis)))
      (setf (my/lifeos-schedule-candidate-condition candidate) 'checking
            (my/lifeos-schedule-candidate-pending-request-id candidate) "new")
      (let ((response (my/lifeos-schedule-test-response candidate)))
        (should-not (my/lifeos-schedule-apply-response
                     candidate (plist-put (copy-tree response) :request-id "old")))
        (should-not (my/lifeos-schedule-apply-response
                     candidate (plist-put (copy-tree response) :revision 99)))
        (should-not (my/lifeos-schedule-apply-response
                     candidate (plist-put (copy-tree response) :verified nil)))
        (should (my/lifeos-schedule-apply-response candidate response))))))

(ert-deftest my/lifeos-schedule-status-precedence-is-deterministic ()
  (my/lifeos-schedule-test-with-planning ""
    (let ((candidate (my/lifeos-schedule-test-candidate)))
      (should (eq (my/lifeos-schedule-status candidate) 'need-info))
      (my/lifeos-schedule-test-make-current candidate :hard-conflicts '("deadline")
                                            :safety-pass nil)
      (should (eq (my/lifeos-schedule-status candidate) 'does-not-fit))
      (my/lifeos-schedule-test-make-current candidate :hard-conflicts nil
                                            :safety-pass nil)
      (should (eq (my/lifeos-schedule-status candidate) 'at-risk))
      (my/lifeos-schedule-test-make-current candidate)
      (should (eq (my/lifeos-schedule-status candidate) 'fits))
      (setf (my/lifeos-schedule-candidate-condition candidate) 'checking)
      (should (eq (my/lifeos-schedule-status candidate) 'need-info)))))

(ert-deftest my/lifeos-schedule-fallback-never-proves-a-conflict-free-fit ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((candidate (my/lifeos-schedule-test-candidate)) response)
      (setf (my/lifeos-schedule-candidate-condition candidate) 'checking
            (my/lifeos-schedule-candidate-pending-request-id candidate) "local")
      (my/lifeos-schedule--local-analysis
       (list :candidate-id (my/lifeos-schedule-candidate-id candidate)
             :revision 0
             :input-fingerprint
             (my/lifeos-schedule-candidate-input-fingerprint candidate)
             :request-id "local"
             :blocks (my/lifeos-schedule-candidate-blocks candidate)
             :fixed-blocks nil :horizon-start 29999900 :horizon-end 30010000)
       (lambda (value) (setq response value)))
      (should-not (plist-get response :complete))
      (should-not (my/lifeos-schedule-apply-response candidate response))
      (should (eq (my/lifeos-schedule-status candidate) 'need-info)))))

(ert-deftest my/lifeos-schedule-builds-strict-v3-candidate-request-from-snapshot ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((block (my/lifeos-schedule-test-block "task-a" 30000000 'keep))
           (request `((protocolVersion . "lifeos-planning/v3")
                      (requestId . "portfolio-request")
                      (horizon . ((start . 29999900) (end . 30010000)))
                      (tasks . [((id . "task-a") (projectId . "project-a")
                                 (durationMinutes . 60) (workType . "explicit")
                                 (fixedStart . :null))])
                      (projects . []) (busy . [((id . "accepted:block")
                                                (start . 30000000) (end . 30000060)
                                                (kind . "accepted-plan"))])
                      (scenario . :null) (candidate . :null)
                      (negotiationQueries . [])))
           (context (list :request-id "portfolio-request"
                          :input-fingerprint "captured-fingerprint"
                          :request request :analysis '(:all-records nil :projects nil)
                          :source-markers (make-hash-table :test #'equal)))
           (candidate (my/lifeos-schedule-create context (list block) nil)))
      (when (timerp my/lifeos-schedule-debounce-timer)
        (cancel-timer my/lifeos-schedule-debounce-timer)
        (setq my/lifeos-schedule-debounce-timer nil))
      (my/lifeos-schedule-place candidate "task-a" 30000120)
      (when (timerp my/lifeos-schedule-debounce-timer)
        (cancel-timer my/lifeos-schedule-debounce-timer)
        (setq my/lifeos-schedule-debounce-timer nil))
      (let* ((analysis-request
              (list :candidate candidate :request-id "schedule-1"))
             (normalized
              (my/lifeos-schedule--normalized-candidate-request analysis-request))
             (candidate-json (alist-get 'candidate normalized)))
        (should (equal (alist-get 'protocolVersion normalized) "lifeos-planning/v3"))
        (should (equal (alist-get 'requestId normalized) "schedule-1"))
        (should-not (append (alist-get 'busy normalized) nil))
        (should (equal (append (alist-get 'exactPlacements candidate-json) nil)
                       '(((taskId . "task-a") (start . 30000120)))))
        (should (equal (alist-get 'capturedInputFingerprint candidate-json)
                       "captured-fingerprint"))))))

(ert-deftest my/lifeos-schedule-candidate-round-trips-through-real-cli ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((root (my/lifeos-solver--solver-root))
           (fixture (expand-file-name "test/fixtures/sat.json" root))
           (request (with-temp-buffer
                      (insert-file-contents fixture)
                      (json-parse-buffer :object-type 'alist :array-type 'array
                                         :null-object :null :false-object :false)))
           (context (list :request-id "sat-fixture"
                          :input-fingerprint "fixture-fingerprint"
                          :request request :analysis '(:all-records nil :projects nil)
                          :source-markers (make-hash-table :test #'equal)))
           (candidate
            (my/lifeos-schedule-create
             context
             (list (list :id "block-research" :kind 'task :task-id "research"
                         :project-id "essay" :source-id "research" :title "Research"
                         :start 60 :end 120 :minutes 60 :role 'keep))
             nil)))
      (when (timerp my/lifeos-schedule-debounce-timer)
        (cancel-timer my/lifeos-schedule-debounce-timer)
        (setq my/lifeos-schedule-debounce-timer nil))
      (my/lifeos-schedule-place candidate "research" 60)
      (when (timerp my/lifeos-schedule-debounce-timer)
        (cancel-timer my/lifeos-schedule-debounce-timer)
        (setq my/lifeos-schedule-debounce-timer nil))
      (my/lifeos-schedule--send-analysis candidate)
      (let ((process (car my/lifeos-schedule-analysis-processes)))
        (while (process-live-p process)
          (accept-process-output process 0.05))
        (accept-process-output process 0.05))
      (should (eq (my/lifeos-schedule-candidate-condition candidate) 'current))
      (should (plist-get (my/lifeos-schedule-candidate-evidence candidate) :verified))
      (should (memq (my/lifeos-schedule-status candidate) '(fits at-risk)))
      (should (seq-find
               (lambda (block)
                 (and (equal (plist-get block :source-id) "research")
                      (= (plist-get block :start) 60)
                      (eq (plist-get block :role) 'moved-user)))
               (my/lifeos-schedule-candidate-blocks candidate))))))

(ert-deftest my/lifeos-schedule-renderer-has-ordered-sections-labels-and-navigation ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((roles '(fixed keep new moved-user moved-plan capacity))
           (blocks (cl-loop for role in (cdr roles) for index from 1
                            collect (my/lifeos-schedule-test-block
                                     (format "s%d" index) (+ 30000000 (* index 75))
                                     role (if (eq role 'capacity)
                                              'project-capacity 'task))))
           (fixed (list (my/lifeos-schedule-test-block "fixed" 30000000 'fixed)))
           (candidate (my/lifeos-schedule-test-candidate blocks fixed)))
      (setf (my/lifeos-schedule-candidate-exclusions candidate)
            (list (my/lifeos-schedule-test-block "excluded" 30001000 'excluded))
            (my/lifeos-schedule-candidate-omissions candidate)
            (list (my/lifeos-schedule-test-block "omitted" 30001100 'omitted)))
      (with-temp-buffer
        (my/lifeos-schedule-mode)
        (setq-local my/lifeos-schedule-buffer-candidate candidate)
        (my/lifeos-schedule-render candidate)
        (let ((text (buffer-string)))
          (dolist (label '("[FIXED]" "[KEEP]" "[NEW]" "[MOVED: USER]"
                           "[MOVED: PLAN]" "[CAP]" "[EXCL]" "[OMIT]"))
            (should (string-match-p (regexp-quote label) text)))
          (should (< (string-match "Schedule" text) (string-match "Omissions" text)))
          (should (< (string-match "Omissions" text)
                     (string-match "Consequences" text))))
        (goto-char (car (my/lifeos-schedule--selectable-positions)))
        (my/lifeos-schedule-previous-block)
        (should (= (point) (car (last (my/lifeos-schedule--selectable-positions)))))
        (dolist (key '("n" "p" "RET" "v" "m" "x" "e" "u" "r" "a"
                       "d" "R" "h" "q"))
          (should (commandp (lookup-key my/lifeos-schedule-mode-map (kbd key)))))))))

(ert-deftest my/lifeos-schedule-boundary-advances-past-in-progress-block ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((old (my/lifeos-schedule-test-block "old" 30000000 'keep))
           (text (my/lifeos-schedule-serialize-plan
                  "p" "f" 30000000 30001000 29999900 (list old))))
      (write-region text nil file nil 'silent)
      (let* ((context (my/lifeos-schedule-test-context 30000030 30001000))
             (candidate (my/lifeos-schedule-create context nil nil)))
        (should (= (my/lifeos-schedule-candidate-horizon-start candidate) 30000060))
        (should (string-match-p "in-progress"
                                (my/lifeos-schedule-candidate-boundary-adjustment
                                 candidate)))))))

(ert-deftest my/lifeos-schedule-acceptance-is-guarded-atomic-and-restorable ()
  (my/lifeos-schedule-test-with-planning "* Policy\n"
    (let* ((candidate (my/lifeos-schedule-test-candidate))
           (_ (my/lifeos-schedule-test-make-current candidate))
           (result (my/lifeos-schedule-accept candidate)))
      (should (= (plist-get result :accepted-blocks) 1))
      (should-not my/lifeos-schedule-active-candidate)
      (should (my/lifeos-schedule-restore-available-p))
      (should (plist-get (my/lifeos-schedule-parse-current-plan) :present-p))
      (should (my/lifeos-schedule-restore))
      (should-not (plist-get (my/lifeos-schedule-parse-current-plan) :present-p))
      (should-not my/lifeos-schedule-restore-token))))

(ert-deftest my/lifeos-schedule-acceptance-refuses-status-dirty-stale-and-fixed-conflict ()
  (my/lifeos-schedule-test-with-planning ""
    (let ((candidate (my/lifeos-schedule-test-candidate)))
      (should-error (my/lifeos-schedule-accept candidate) :type 'user-error)
      (my/lifeos-schedule-test-make-current candidate :safety-pass nil)
      (should-error (my/lifeos-schedule-accept candidate) :type 'user-error)
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max)) (insert "dirty"))
      (should-error (my/lifeos-schedule-accept candidate t) :type 'user-error)))
  (my/lifeos-schedule-test-with-planning ""
    (let ((candidate (my/lifeos-schedule-test-candidate)))
      (my/lifeos-schedule-test-make-current candidate)
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (insert "* Changed policy\n")
        (let ((before-save-hook nil)) (save-buffer)))
      (should-error (my/lifeos-schedule-accept candidate) :type 'user-error)
      (should (eq (my/lifeos-schedule-candidate-condition candidate) 'stale))))
  (my/lifeos-schedule-test-with-planning ""
    (let* ((fixed (my/lifeos-schedule-test-block "fixed" 30000000 'fixed))
           (candidate (my/lifeos-schedule-test-candidate nil (list fixed))))
      (my/lifeos-schedule-test-make-current candidate)
      (should-error (my/lifeos-schedule-accept candidate) :type 'user-error))))

(ert-deftest my/lifeos-schedule-save-failure-rolls-back-buffer-and-file ()
  (my/lifeos-schedule-test-with-planning "* Policy\n"
    (let* ((candidate (my/lifeos-schedule-test-candidate))
           (_ (my/lifeos-schedule-test-make-current candidate))
           (before (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (cl-letf (((symbol-function 'save-buffer) (lambda (&rest _) (error "injected"))))
        (should-error (my/lifeos-schedule-accept candidate) :type 'user-error))
      (should (equal before
                     (with-temp-buffer (insert-file-contents file) (buffer-string))))
      (with-current-buffer (find-file-noselect file)
        (should (equal before (buffer-string)))
        (should-not (buffer-modified-p))))))

(ert-deftest my/lifeos-schedule-current-plan-projects-as-attributed-flexible-busy ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((block (my/lifeos-schedule-test-block
                   "project-z" 30000000 'capacity 'project-capacity))
           (text (my/lifeos-schedule-serialize-plan
                  "p" "f" 30000000 30001000 29999900 (list block))))
      (write-region text nil file nil 'silent)
      (let ((busy (append (my/lifeos-schedule-current-plan-busy
                           29999900 30001000) nil)))
        (should (= (length busy) 1))
        (should (equal (alist-get 'kind (car busy)) "accepted-plan"))
        (should (equal (alist-get 'sourceId
                                  (alist-get 'evidence (car busy)))
                       "project-z"))))))

(ert-deftest my/lifeos-schedule-parser-rejects-overlap-and-split-task ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((one (my/lifeos-schedule-test-block "same" 30000000 'keep))
           (two (plist-put (my/lifeos-schedule-test-block
                            "same" 30000060 'keep)
                           :id "block-same-2"))
           (text (my/lifeos-schedule-serialize-plan
                  "p" "f" 30000000 30001000 29999900 (list one two))))
      (write-region text nil file nil 'silent)
      (should (string-match-p
               "split or duplicated"
               (car (plist-get (my/lifeos-schedule-parse-current-plan) :issues))))))
  (my/lifeos-schedule-test-with-planning ""
    (let* ((one (my/lifeos-schedule-test-block "one" 30000000 'keep))
           (two (my/lifeos-schedule-test-block "two" 30000030 'keep))
           (text (my/lifeos-schedule-serialize-plan
                  "p" "f" 30000000 30001000 29999900 (list one two))))
      (write-region text nil file nil 'silent)
      (should (string-match-p
               "overlap"
               (car (plist-get (my/lifeos-schedule-parse-current-plan) :issues)))))))

(ert-deftest my/lifeos-schedule-acceptance-refuses-new-boundary-intersection ()
  (my/lifeos-schedule-test-with-planning ""
    (let* ((old (my/lifeos-schedule-test-block "old" 30000000 'keep))
           (initial (my/lifeos-schedule-serialize-plan
                     "old" "f" 30000000 30001000 29999900 (list old))))
      (write-region initial nil file nil 'silent)
      (let* ((context (my/lifeos-schedule-test-context 30000120 30001000))
             (candidate (my/lifeos-schedule-create
                         context (list (my/lifeos-schedule-test-block
                                        "new" 30000200 'new)) nil))
             (intersecting
              (my/lifeos-schedule-test-block "intersecting" 30000090 'keep)))
        (when (timerp my/lifeos-schedule-debounce-timer)
          (cancel-timer my/lifeos-schedule-debounce-timer))
        (my/lifeos-schedule-test-make-current candidate)
        (with-current-buffer (find-file-noselect file)
          (let ((parsed (my/lifeos-schedule-parse-current-plan (current-buffer)))
                (replacement (my/lifeos-schedule-serialize-plan
                              "changed" "f" 30000000 30001000 29999900
                              (list intersecting))))
            (my/lifeos-schedule--replace-subtree (current-buffer) parsed replacement)
            (let ((before-save-hook nil)) (save-buffer))))
        (setf (my/lifeos-schedule-candidate-current-plan-fingerprint candidate)
              (plist-get (my/lifeos-schedule-parse-current-plan) :fingerprint))
        (should-error (my/lifeos-schedule-accept candidate) :type 'user-error)
        (should (eq my/lifeos-schedule-active-candidate candidate))))))

(ert-deftest my/lifeos-schedule-restore-refuses-intervening-plan-change ()
  (my/lifeos-schedule-test-with-planning "* Policy\n"
    (let ((candidate (my/lifeos-schedule-test-candidate)))
      (my/lifeos-schedule-test-make-current candidate)
      (my/lifeos-schedule-accept candidate)
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-max))
        (insert "# manual change\n")
        (let ((before-save-hook nil)) (save-buffer)))
      (should-not (my/lifeos-schedule-restore-available-p))
      (should-error (my/lifeos-schedule-restore) :type 'user-error))))

(provide 'lifeos-schedule-test)
;;; lifeos-schedule-test.el ends here
