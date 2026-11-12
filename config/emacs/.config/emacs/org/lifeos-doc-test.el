;;; lifeos-doc-test.el --- Documentation integrity tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'org-element)
(defconst my/lifeos-doc-test-module-directory
  (file-name-directory (or load-file-name buffer-file-name)))

(let ((directory my/lifeos-doc-test-module-directory))
  (add-to-list 'load-path directory)
  (load (expand-file-name "lifeos-planning.el" directory) nil t)
  (load (expand-file-name "lifeos-forecast.el" directory) nil t)
  (load (expand-file-name "lifeos-solver.el" directory) nil t)
  (load (expand-file-name "lifeos-agenda.el" directory) nil t)
  (autoload 'my/org-gcal-fetch (expand-file-name "org-gcal.el" directory) nil t)
  (autoload 'my/org-gcal-full-refresh (expand-file-name "org-gcal.el" directory) nil t))

(defconst my/lifeos-doc-test-directory
  (expand-file-name "~/Work/lifeos/docs/lifeos/"))

(defun my/lifeos-doc-test-files ()
  "Return active LifeOS manual Org files."
  (directory-files my/lifeos-doc-test-directory t "\\.org\\'"))

(defun my/lifeos-doc-test-file-text (name)
  "Return the manual file NAME as text."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name my/lifeos-doc-test-directory))
    (buffer-string)))

(ert-deftest my/lifeos-manual-local-file-and-heading-links-resolve ()
  (dolist (source (my/lifeos-doc-test-files))
    (with-temp-buffer
      (insert-file-contents source)
      (org-mode)
      (org-element-map (org-element-parse-buffer) 'link
        (lambda (link)
          (when (equal (org-element-property :type link) "file")
            (let* ((path (org-element-property :path link))
                   (target (if (file-name-absolute-p path) path
                             (expand-file-name path (file-name-directory source))))
                   (heading (org-element-property :search-option link)))
              (should (file-exists-p target))
              (when (and heading (string-suffix-p ".org" target))
                (with-temp-buffer
                  (insert-file-contents target)
                  (goto-char (point-min))
                  (should (re-search-forward
                           (format "^\\*+ +%s[ \\t]*$"
                                   (regexp-quote
                                    (string-trim-left heading "\\*+")))
                           nil t)))))))))))

(ert-deftest my/lifeos-manual-documented-commands-exist ()
  (dolist (command '(org-capture org-agenda my/lifeos-agenda
                       my/lifeos-agenda-refresh my/lifeos-explain-at-point
                      my/lifeos-next-diagnostic my/lifeos-previous-diagnostic
                      my/lifeos-groom-task my/lifeos-needs-grooming
                      my/lifeos-break-down-task my/lifeos-set-remaining-effort
                      my/lifeos-refresh-buffer-diagnostics
                      my/lifeos-refresh-project-analysis
                      my/lifeos-groom-project my/lifeos-settings
                     my/lifeos-solver-show-portfolio-review
                     my/lifeos-scheduling-review-fixture
                     my/lifeos-scheduling-review-live
                     my/lifeos-solver-show-shadow-result
                     my/lifeos-solver-show-raw-json
                     my/lifeos-solver-show-discrepancies
                     my/lifeos-solver-scenario-menu my/lifeos-solver-negotiate
                     my/org-gcal-fetch my/org-gcal-full-refresh))
    (should (commandp command))))

(ert-deftest my/lifeos-manual-leader-bindings-match-configuration ()
  (let ((leader-file
         (expand-file-name
          "../leader/general.el"
          my/lifeos-doc-test-module-directory)))
    (with-temp-buffer
      (insert-file-contents leader-file)
      (let ((source (buffer-string)))
         (dolist (binding '(("n a" . my/lifeos-agenda)
                            ("n A" . org-agenda)
                            ("n p e" . my/lifeos-explain-at-point)
                           ("n p n" . my/lifeos-next-diagnostic)
                           ("n p p" . my/lifeos-previous-diagnostic)
                           ("n p m" . my/lifeos-groom-project)
                           ("n p c" . my/lifeos-settings)
                           ("n p P" . my/lifeos-solver-show-portfolio-review)
                           ("n p s" . my/lifeos-solver-show-shadow-result)
                           ("n p j" . my/lifeos-solver-show-raw-json)
                           ("n p d" . my/lifeos-solver-show-discrepancies)
                           ("n p S" . my/lifeos-solver-scenario-menu)
                           ("n p q" . my/lifeos-solver-negotiate)
                           ("n p g" . my/org-gcal-fetch)
                           ("n p G" . my/org-gcal-full-refresh)))
          (should (string-match-p
                   (format "\\\"%s\\\"[[:space:]]+'(%s"
                           (regexp-quote (car binding)) (regexp-quote (symbol-name (cdr binding))))
                   source)))))))

(ert-deftest my/lifeos-manual-enums-match-canonical-vocabularies ()
  (let ((reference (expand-file-name "reference.org" my/lifeos-doc-test-directory)))
    (with-temp-buffer
      (insert-file-contents reference)
      (let ((text (buffer-string)))
        (dolist (value my/lifeos-impact-values) (should (string-match-p (regexp-quote value) text)))
        (dolist (value my/lifeos-work-mode-values) (should (string-match-p (regexp-quote value) text)))
        (dolist (value my/lifeos-estimate-confidence-values)
          (should (string-match-p (regexp-quote value) text)))))))

(ert-deftest my/lifeos-manual-schedule-candidate-controls-are-complete ()
  (let ((text (my/lifeos-doc-test-file-text "reference.org")))
    (dolist (key '("s" "n" "p" "RET" "v" "m" "x" "e" "u" "r" "a" "d" "R" "h" "q"))
      (should (string-match-p
               (format "=%s=" (regexp-quote key)) text)))
    (dolist (action '("opens a schedule candidate from the displayed current snapshot"
                      "Next/previous selectable block"
                      "Open selected block details"
                      "Visit snapshot-bound task or project source"
                      "Place selected task at an exact aligned start"
                      "Exclude selected task demand or coarse reservation"
                      "Set a draft-only candidate estimate"
                      "Undo latest candidate edit"
                      "Regenerate stale input"
                      "Review and accept the complete candidate"
                      "Discard the complete candidate"
                      "Restore the immediately previous accepted plan"
                      "Open contextual help"
                      "Quit the window without accepting"))
      (should (string-match-p (regexp-quote action) text)))))

(ert-deftest my/lifeos-manual-schedule-candidate-vocabularies-are-complete ()
  (let ((reference (my/lifeos-doc-test-file-text "reference.org"))
        (workflow (my/lifeos-doc-test-file-text "schedule-candidates.org")))
    (dolist (value '("EDITING" "CHECKING" "CURRENT" "STALE"))
      (should (string-match-p (regexp-quote value) reference))
      (should (string-match-p (regexp-quote value) workflow)))
    (dolist (value '("NEED INFO" "DOES NOT FIT" "AT RISK" "FITS"))
      (should (string-match-p (regexp-quote value) reference))
      (should (string-match-p (regexp-quote value) workflow)))
    (dolist (label '("[FIXED]" "[KEEP]" "[NEW]" "[MOVED: USER]"
                     "[MOVED: PLAN]" "[CAP]" "[EXCL]" "[OMIT]"))
      (should (string-match-p (regexp-quote label) workflow)))))

(ert-deftest my/lifeos-manual-accepted-schedule-vocabulary-is-complete ()
  (let ((text (my/lifeos-doc-test-file-text "reference.org")))
    (dolist (value '("Accepted schedule"
                     "LIFEOS_PLAN_ID"
                     "LIFEOS_PLAN_SOURCE_FINGERPRINT"
                     "LIFEOS_PLAN_HORIZON_START"
                     "LIFEOS_PLAN_HORIZON_END"
                     "LIFEOS_PLAN_ACCEPTED_AT"
                     "LIFEOS_PLAN_KIND"
                     "LIFEOS_PLAN_TASK_ID"
                     "LIFEOS_PLAN_PROJECT_ID"
                     "LIFEOS_PLAN_START"
                     "LIFEOS_PLAN_END"
                     "LIFEOS_PLAN_MINUTES"
                     "TASK"
                     "PROJECT_CAPACITY"
                     "SCHEDULED"))
      (should (string-match-p (regexp-quote value) text)))))

(ert-deftest my/lifeos-manual-excludes-historical-transcripts ()
  (dolist (source (my/lifeos-doc-test-files))
    (with-temp-buffer
      (insert-file-contents source)
      (should-not (string-match-p "\\[\\[file:.*\\.agent-shell/transcripts"
                                  (buffer-string))))))

(provide 'lifeos-doc-test)
