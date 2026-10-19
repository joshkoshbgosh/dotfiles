;;; lifeos-agenda-test.el --- Tests for the LifeOS agenda -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(defconst my/lifeos-agenda-test-directory
  (file-name-directory (or load-file-name buffer-file-name)))

(let ((directory my/lifeos-agenda-test-directory))
  (load (expand-file-name "lifeos-planning.el" directory) nil t)
  (load (expand-file-name "lifeos-forecast.el" directory) nil t)
  (load (expand-file-name "lifeos-schedule.el" directory) nil t)
  (load (expand-file-name "lifeos-solver.el" directory) nil t)
  (load (expand-file-name "lifeos-agenda.el" directory) nil t))

(defmacro my/lifeos-agenda-test-with-buffers (&rest body)
  "Run BODY with live source and agenda buffers."
  (declare (indent 0) (debug t))
  `(let ((source (generate-new-buffer " *lifeos-agenda-source*"))
         (agenda (generate-new-buffer " *lifeos-agenda-test*")))
     (unwind-protect
         (progn
           (with-current-buffer source
             (org-mode)
             (setq-local org-todo-keywords
                         '((sequence "TODO" "NEXT" "WAITING" "SOMEDAY"
                                     "|" "DONE" "CANCELLED"))))
           (with-current-buffer agenda (org-agenda-mode))
           ,@body)
       (kill-buffer source)
       (kill-buffer agenda))))

(ert-deftest my/lifeos-agenda-command-is-the-dashboard ()
  (let ((command (assoc "d" org-agenda-custom-commands)))
    (should command)
    (should (equal (nth 1 command) "LifeOS dashboard"))
    (should (eq (nth 2 command) 'agenda))
    (should (string-match-p "my/lifeos-agenda--append-dashboard"
                            (prin1-to-string command)))))

(ert-deftest my/lifeos-agenda-ready-renders-only-unblocked-valid-work ()
  (my/lifeos-agenda-test-with-buffers
    (let (ready-marker blocked-marker)
      (with-current-buffer source
        (insert "* TODO Ready #task\n* TODO Blocked #task\n")
        (goto-char (point-min))
        (setq ready-marker (copy-marker (point)))
        (forward-line 1)
        (setq blocked-marker (copy-marker (point))))
      (let* ((ready (list :id "ready" :title "Ready" :state "TODO"
                          :eligible t :executable t :minutes 20
                          :work-mode "Shallow" :priority "B" :impact "High"
                          :marker ready-marker))
             (blocked (list :id "blocked" :title "Blocked" :state "TODO"
                            :eligible t :executable t :minutes 30
                            :priority "A" :impact "High" :marker blocked-marker))
             (snapshot (list :analysis
                             (list :all-records (list ready blocked)
                                   :edges '(("ready") ("blocked" "dependency"))))))
        (with-current-buffer agenda
          (setq-local my/lifeos-agenda--snapshot snapshot)
          (cl-letf (((symbol-function 'my/lifeos-agenda--refresh-snapshot)
                     (lambda () my/lifeos-agenda--snapshot)))
            (my/lifeos-agenda-ready ""))
          (let ((text (buffer-string)))
            (should (string-match-p "Ready" text))
            (should-not (string-match-p "Blocked" text)))
          (goto-char (point-min))
          (forward-line 1)
          (should (eq (marker-buffer (org-get-at-bol 'org-marker)) source)))))))

(ert-deftest my/lifeos-agenda-status-renders-computed-meta-values ()
  (my/lifeos-agenda-test-with-buffers
    (let ((summaries (make-hash-table :test #'equal)))
      (puthash "project" '(:unplaced-count 2) summaries)
      (with-current-buffer agenda
        (setq-local my/lifeos-agenda--snapshot
                    (list :analysis
                          '(:invalid-records (bad)
                            :projects ((:definition-status incomplete)))
                          :forecast '(:data-errors (one two three))
                          :summaries summaries))
        (cl-letf (((symbol-function 'my/lifeos-solver--portfolio-evidence-state)
                   (lambda (&rest _) "CURRENT"))
                  ((symbol-function 'my/lifeos-schedule-portfolio-status)
                   (lambda (&rest _) "AT RISK"))
                  ((symbol-function 'my/lifeos-agenda--calendar-status)
                   (lambda () "STALE")))
          (my/lifeos-agenda-status ""))
        (let ((text (buffer-string)))
          (should (string-match-p "Planning: AT RISK" text))
          (should (string-match-p "Evidence: CURRENT" text))
          (should (string-match-p "Calendar: STALE" text))
          (should (string-match-p "Needs info: 3 headings, 1 projects" text))
          (should (string-match-p "Unplaced: 2" text)))
        (goto-char (point-min))
        (forward-line 1)
        (should (eq (get-text-property (point) 'lifeos-agenda-target)
                    'status))))))

(ert-deftest my/lifeos-agenda-projects-groups-all-projects-by-attention ()
  (my/lifeos-agenda-test-with-buffers
    (let (risk-marker local-marker inactive-marker
          (summaries (make-hash-table :test #'equal)))
      (with-current-buffer source
        (insert "* TODO Risk #project\n* TODO Local #project\n* SOMEDAY Later #project\n")
        (goto-char (point-min))
        (setq risk-marker (copy-marker (point)))
        (forward-line 1)
        (setq local-marker (copy-marker (point)))
        (forward-line 1)
        (setq inactive-marker (copy-marker (point))))
      (puthash "risk" '(:unplaced-count 1 :left-minutes 60) summaries)
      (puthash "local" '(:unplaced-count 0 :left-minutes 30 :tightness 60) summaries)
      (puthash "later" '(:unplaced-count 0 :left-minutes 0) summaries)
      (with-current-buffer agenda
        (setq-local
         my/lifeos-agenda--snapshot
         (list
          :analysis
          (list :projects
                (list
                 (list :key "risk" :title "Risk" :id "risk"
                       :commitment 'committed :definition-status 'detailed
                       :remaining-effort-minutes 60 :marker risk-marker)
                 (list :key "local" :title "Local" :id "local"
                       :commitment 'committed :definition-status 'detailed
                       :remaining-effort-minutes 30 :marker local-marker)
                 (list :key "later" :title "Later" :id "later" :state "SOMEDAY"
                       :commitment 'uncommitted :definition-status 'detailed
                       :marker inactive-marker)))
          :summaries summaries))
        (cl-letf (((symbol-function 'my/lifeos-solver--portfolio-evidence-state)
                   (lambda (&rest _) "LOCAL ONLY")))
          (my/lifeos-agenda-projects ""))
        (let ((text (buffer-string)))
          (should (string-match-p "Projects needing attention" text))
          (should (string-match-p "AT RISK[[:space:]]+Risk" text))
          (should (string-match-p "Projects on track" text))
          (should (string-match-p "LOCAL[[:space:]]+Local" text))
          (should (string-match-p "Inactive / uncommitted projects" text))
          (should (string-match-p "INACTIVE[[:space:]]+Later" text)))
        (goto-char (point-min))
        (search-forward "Risk")
        (beginning-of-line)
        (should (eq (marker-buffer (org-get-at-bol 'org-marker)) source))))))

(ert-deftest my/lifeos-agenda-status-is-an-embark-target ()
  (with-temp-buffer
    (org-agenda-mode)
    (let ((inhibit-read-only t))
      (insert (propertize "Planning status\n"
                          'lifeos-agenda-target 'status)))
    (goto-char (point-min))
    (pcase-let ((`(,type ,_target ,start . ,end)
                 (my/lifeos-agenda--embark-target)))
      (should (eq type 'lifeos-status))
      (should (= start (line-beginning-position)))
      (should (= end (line-end-position))))))

(provide 'lifeos-agenda-test)
