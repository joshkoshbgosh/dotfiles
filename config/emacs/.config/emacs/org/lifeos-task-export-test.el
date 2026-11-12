;;; lifeos-task-export-test.el --- isolated task export tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'json)
(load (expand-file-name "lifeos-task-export.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(defvar supertag--initialized nil)

(ert-deftest lifeos-task-export-refuses-uninitialized-store ()
  (let ((supertag--initialized nil))
    (should-error (my/lifeos-export-task-snapshot "/tmp/unused.json" "/tmp" "UTC"))))

(ert-deftest lifeos-task-export-rejects-stale-index-without-writing ()
  (let* ((root (make-temp-file "lifeos-export-" t))
         (source (expand-file-name "task.org" root))
         (output (make-temp-file "lifeos-snapshot-")))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert "* TODO New name #task\n:PROPERTIES:\n:ID: id-1\n:END:\nDEADLINE: <2026-11-09 Mon>\n"))
          (let ((supertag--initialized t))
            (cl-letf (((symbol-function 'supertag-dirty-p) (lambda () nil))
                      ((symbol-function 'supertag-api-query) (lambda (&rest _) '(:truncated nil :count 1 :nodes ((:id "id-1")))))
                      ((symbol-function 'supertag-api-node)
                       (lambda (_) (list :id "id-1" :title "Old name" :file source
                                         :properties '(:EFFORT "0:30")
                                         :tags '((:id "f2d7075f-d8a8-45c0-9e44-40270fb9e99d" :name "task"))))))
              (my/lifeos-export-task-snapshot output root "UTC")))
          (let* ((data (json-parse-string (with-temp-buffer (insert-file-contents output) (buffer-string))
                                          :object-type 'alist :array-type 'list)))
            (should (eq (alist-get 'complete data) :false))
            (should-not (alist-get 'tasks data))))
      (delete-directory root t)
      (delete-file output))))

(ert-deftest lifeos-task-export-empty-query-is-not-proof-of-withdrawal ()
  (let ((root (make-temp-file "lifeos-export-" t))
        (output (make-temp-file "lifeos-snapshot-"))
        (supertag--initialized t))
    (unwind-protect
        (cl-letf (((symbol-function 'supertag-dirty-p) (lambda () nil))
                  ((symbol-function 'supertag-api-query)
                   (lambda (&rest _) '(:truncated nil :count 0 :nodes nil)))
                  ((symbol-function 'supertag-api-node) (lambda (&rest _) nil)))
          (my/lifeos-export-task-snapshot output root "UTC")
          (should (eq :false (alist-get 'complete
                                       (json-parse-string
                                        (with-temp-buffer (insert-file-contents output) (buffer-string))
                                        :object-type 'alist)))))
      (delete-directory root t)
      (delete-file output))))

;;; Acquisition receipt, reuse and staleness evidence

(defconst lifeos-task-export-test--tag-id
  "f2d7075f-d8a8-45c0-9e44-40270fb9e99d")

(defconst lifeos-task-export-test--project-tag-id
  "1988054a-d048-49ce-bd20-4eb4f9a6f458")

(defun lifeos-task-export-test--source (&optional effort)
  "Return an Org task source with a stable ID and EFFORT."
  (format "* TODO Prepare report #task\n:PROPERTIES:\n:ID: id-1\n:END:\nDEADLINE: <2026-11-12 Thu>\nEFFORT: %s\n"
          (or effort "0:30")))

(defun lifeos-task-export-test--read (path)
  "Return PATH decoded as JSON."
  (with-temp-buffer
    (insert-file-contents path)
    (json-parse-string (buffer-string) :object-type 'alist :array-type 'list)))

(defun lifeos-task-export-test--raw (path)
  "Return PATH bytes as a string."
  (with-temp-buffer (insert-file-contents path) (buffer-string)))

(defmacro lifeos-task-export-test--with-acquisition (&rest body)
  "Run BODY with an isolated vault, output and public Supertag stubs."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "lifeos-acq-root-" t))
          (source (expand-file-name "tasks.org" root))
          (state (make-temp-file "lifeos-acq-out-" t))
          (output (expand-file-name "snapshot.json" state))
          (rescan-calls 0)
          (supertag--initialized t)
          (my/lifeos-task-acquisition-output output)
          (my/lifeos-task-acquisition-root root)
          (my/lifeos-task-acquisition-zone "UTC")
          (my/lifeos-task-acquisition-auto-start nil))
     (unwind-protect
         (progn
           (with-temp-file source (insert (lifeos-task-export-test--source)))
           (cl-letf (((symbol-function 'supertag-dirty-p) (lambda () nil))
                     ((symbol-function 'supertag-api-query)
                      (lambda (&rest _)
                        '(:truncated nil :count 1 :nodes ((:id "id-1")))))
                     ((symbol-function 'supertag-api-node)
                      (lambda (_)
                        (list :id "id-1" :title "Prepare report" :file source
                              :properties '(:EFFORT "0:30")
                              :tags (list (list :id lifeos-task-export-test--tag-id
                                                :name "task")))))
                     ((symbol-function 'supertag-scan-sync-directories)
                      (lambda (&optional _)
                        (directory-files-recursively root "\\.org$")))
                     ((symbol-function 'supertag-sync-full-rescan)
                      (lambda ()
                        (cl-incf rescan-calls)
                        (let ((files (directory-files-recursively root "\\.org$")))
                          (list :status 'complete
                                :files-discovered (length files)
                                :files-processed (length files))))))
             ,@body))
       (delete-directory root t)
       (delete-directory state t))))

(ert-deftest lifeos-task-export-acquisition-writes-trusted-v2 ()
  (lifeos-task-export-test--with-acquisition
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (let ((data (lifeos-task-export-test--read output)))
      (should (equal (alist-get 'version data) 2))
      (should (eq (alist-get 'complete data) t))
      (should (equal (alist-get 'scanStatus data) "complete"))
      (should (equal (alist-get 'filesDiscovered data) 1))
      (should (equal (alist-get 'filesProcessed data) 1))
      (should (string-prefix-p "v2:" (alist-get 'fileSetFingerprint data)))
      (should (equal (length (alist-get 'tasks data)) 1))
      (should (equal (alist-get 'id (car (alist-get 'tasks data))) "id-1"))
      (should (equal (alist-get 'membership
                                (car (alist-get 'tasks data)))
                     '((tagId . "f2d7075f-d8a8-45c0-9e44-40270fb9e99d")
                       (via . "supertag-api-query/node")))))))

(ert-deftest lifeos-task-export-includes-deadline-project-as-evidence ()
  (lifeos-task-export-test--with-acquisition
    (let* ((project-file (expand-file-name "projects.org" root))
           (project-text "* Essay 2 #project\nDEADLINE: <2026-11-25 Wed>\n:PROPERTIES:\n:ID: project-1\n:END:\n"))
      (with-temp-file project-file (insert project-text))
      (cl-letf (((symbol-function 'supertag-api-query)
                 (lambda (&rest _)
                   '(:truncated nil :count 2 :nodes ((:id "id-1") (:id "project-1")))))
                ((symbol-function 'supertag-api-node)
                 (lambda (id)
                   (if (equal id "project-1")
                       (list :id id :title "Essay 2" :file project-file
                             :properties nil
                             :tags (list (list :id lifeos-task-export-test--project-tag-id
                                               :name "project")))
                     (list :id id :title "Prepare report" :file source
                           :properties '(:EFFORT "0:30")
                           :tags (list (list :id lifeos-task-export-test--tag-id
                                             :name "task")))))))
        (my/lifeos-acquire-task-snapshot output root "UTC")))
    (let* ((data (lifeos-task-export-test--read output))
           (tasks (alist-get 'tasks data))
           (project (cl-find-if (lambda (task) (equal (alist-get 'id task) "project-1")) tasks)))
      (should (eq (alist-get 'complete data) t))
      (should project)
      (should (equal (alist-get 'kind project) "project"))
      (should (equal (alist-get 'tagId (alist-get 'membership project))
                     lifeos-task-export-test--project-tag-id))
      (should (eq (alist-get 'effort project) :null)))))

(ert-deftest lifeos-task-export-acquisition-reuses-unchanged-rescan ()
  (lifeos-task-export-test--with-acquisition
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (let* ((first (lifeos-task-export-test--read output))
           (acquisition-id (alist-get 'acquisitionId first)))
      (setq rescan-calls 0)
      (cl-letf (((symbol-function 'supertag-sync-full-rescan)
                 (lambda () (error "complete rescan must be reused"))))
        (my/lifeos-acquire-task-snapshot output root "UTC"))
      (should (= rescan-calls 0))
      (let ((second (lifeos-task-export-test--read output)))
        (should (equal (alist-get 'acquisitionId second) acquisition-id))
        (should (eq (alist-get 'complete second) t))))))

(ert-deftest lifeos-task-export-acquisition-rescans-when-source-changes ()
  (lifeos-task-export-test--with-acquisition
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (setq rescan-calls 0)
    (with-temp-file source
      (insert (lifeos-task-export-test--source "1:00")))
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (should (= rescan-calls 1))
    (should (eq (alist-get 'complete (lifeos-task-export-test--read output)) t))))

(ert-deftest lifeos-task-export-acquisition-aborts-on-mid-window-modification ()
  (lifeos-task-export-test--with-acquisition
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (let ((before (lifeos-task-export-test--raw output)))
      ;; Change the source so the fingerprint differs, then let the rescan write
      ;; it again after the acquisition start instant.
      (with-temp-file source (insert (lifeos-task-export-test--source "1:00")))
      (cl-letf (((symbol-function 'supertag-sync-full-rescan)
                 (lambda ()
                   (with-temp-file source
                     (insert (lifeos-task-export-test--source "2:00")))
                   (list :status 'complete
                         :files-discovered 1 :files-processed 1))))
        (should-error (my/lifeos-acquire-task-snapshot output root "UTC")))
      (should (equal (lifeos-task-export-test--raw output) before)))))

(ert-deftest lifeos-task-export-acquisition-aborts-on-file-set-change ()
  (lifeos-task-export-test--with-acquisition
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (let ((before (lifeos-task-export-test--raw output)))
      (with-temp-file source (insert (lifeos-task-export-test--source "1:00")))
      (cl-letf (((symbol-function 'supertag-sync-full-rescan)
                 (lambda ()
                   (with-temp-file (expand-file-name "extra.org" root)
                     (insert "* TODO Extra #task\n"))
                   (list :status 'complete
                         :files-discovered 1 :files-processed 1))))
        (should-error (my/lifeos-acquire-task-snapshot output root "UTC")))
      (should (equal (lifeos-task-export-test--raw output) before)))))

(ert-deftest lifeos-task-export-acquisition-rejects-incomplete-rescan ()
  (lifeos-task-export-test--with-acquisition
    (cl-letf (((symbol-function 'supertag-sync-full-rescan)
               (lambda ()
                 (list :status 'aborted :snapshot-status 'partial
                       :files-discovered 1 :files-processed 0))))
      (should-error (my/lifeos-acquire-task-snapshot output root "UTC")))
    (should-not (file-exists-p output))))

(ert-deftest lifeos-task-export-acquisition-rejects-count-disagreement ()
  (lifeos-task-export-test--with-acquisition
    (cl-letf (((symbol-function 'supertag-sync-full-rescan)
               (lambda ()
                 (list :status 'complete
                       :files-discovered 1 :files-processed 0))))
      (should-error (my/lifeos-acquire-task-snapshot output root "UTC")))
    (should-not (file-exists-p output))))

(ert-deftest lifeos-task-export-acquisition-does-not-reuse-administrative-v1 ()
  (lifeos-task-export-test--with-acquisition
    (my/lifeos-export-task-snapshot output root "UTC")
    (should (equal (alist-get 'version (lifeos-task-export-test--read output)) 1))
    (setq rescan-calls 0)
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (should (= rescan-calls 1))
    (should (equal (alist-get 'version (lifeos-task-export-test--read output)) 2))))

(ert-deftest lifeos-task-export-acquisition-timer-requires-configuration ()
  (let ((my/lifeos-task-acquisition-output nil)
        (my/lifeos-task-acquisition-root nil)
        (my/lifeos-task-acquisition-zone nil))
    (should-error (my/lifeos-task-acquisition-start) :type 'user-error)))

(ert-deftest lifeos-task-export-acquisition-timer-starts-and-stops ()
  (let ((my/lifeos-task-acquisition-output "/tmp/lifeos-unused-snapshot.json")
        (my/lifeos-task-acquisition-root "/tmp")
        (my/lifeos-task-acquisition-zone "UTC")
        (my/lifeos-task-acquisition-interval 3600))
    (unwind-protect
        (progn
          (should (timerp (my/lifeos-task-acquisition-start)))
          (should (timerp my/lifeos-task-acquisition--timer)))
      (my/lifeos-task-acquisition-stop))
    (should-not my/lifeos-task-acquisition--timer)))

(ert-deftest lifeos-task-export-acquisition-tick-pauses-on-dirty-store ()
  (lifeos-task-export-test--with-acquisition
    (let ((my/lifeos-task-acquisition--pause-reason nil))
      (cl-letf (((symbol-function 'supertag-dirty-p) (lambda () t)))
        ;; A dirty session cannot prove a clean index; the tick must not rescan or
        ;; write a snapshot, and it must report the pause reason once.
        (my/lifeos-task-acquisition-tick)
        (should-not (file-exists-p output))
        (should (equal my/lifeos-task-acquisition--pause-reason
                       "Supertag has unsaved store changes"))
        (should (= rescan-calls 0))))))

(ert-deftest lifeos-task-export-acquisition-tick-clears-pause-after-success ()
  (lifeos-task-export-test--with-acquisition
    (let ((my/lifeos-task-acquisition--pause-reason nil)
          (dirty t))
      (cl-letf (((symbol-function 'supertag-dirty-p) (lambda () dirty)))
        (my/lifeos-task-acquisition-tick)
        (should my/lifeos-task-acquisition--pause-reason)
        (setq dirty nil)
        (my/lifeos-task-acquisition-tick))
      (should-not my/lifeos-task-acquisition--pause-reason)
      (should (file-exists-p output)))))

(ert-deftest lifeos-task-export-does-not-run-user-org-mode-hooks ()
  (lifeos-task-export-test--with-acquisition
    (let ((hook-ran nil))
      ;; A live config may add hooks that modify the buffer or prompt. The
      ;; disposable parse buffer must not run them.
      (let ((org-mode-hook (list (lambda () (setq hook-ran t)))))
        (my/lifeos-acquire-task-snapshot output root "UTC"))
      (should-not hook-ran)
      (should (eq (alist-get 'complete (lifeos-task-export-test--read output)) t)))))

(ert-deftest lifeos-task-export-never-kills-a-modified-file-visiting-buffer ()
  (lifeos-task-export-test--with-acquisition
    (let* ((original (symbol-function 'kill-buffer))
           (modified-file-kills nil))
      ;; Emacs 31 asks `kill-buffer--possibly-save' (yes/no/save) when an
      ;; interactive Emacs kills a modified buffer that visits a file. The
      ;; parse buffer visits the vault file, so a stale modified flag would
      ;; block the server and offer to save over the vault.
      (cl-letf (((symbol-function 'kill-buffer)
                 (lambda (&optional buffer-or-name)
                   (let ((buffer (get-buffer buffer-or-name)))
                     (when (and buffer (buffer-modified-p buffer)
                                (buffer-local-value 'buffer-file-name buffer))
                       (push (buffer-name buffer) modified-file-kills)))
                   (funcall original buffer-or-name))))
        (my/lifeos-acquire-task-snapshot output root "UTC"))
      (should-not modified-file-kills))))

(ert-deftest lifeos-task-export-carries-a03-policy-facts ()
  (lifeos-task-export-test--with-acquisition
    (with-temp-file source
      (insert "* TODO Prepare report #task
DEADLINE: <2026-11-12 Thu> SCHEDULED: <2026-11-11 Wed 10:00>
:PROPERTIES:
:ID: id-1
:WORK_MODE: Deep
:WAIT_UNTIL: <2026-11-11 Wed 09:00>
:EFFORT: 1:00
:END:
[[depends-on:prereq-a]]
"))
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (let* ((data (lifeos-task-export-test--read output))
           (task (car (alist-get 'tasks data))))
      (should (eq (alist-get 'complete data) t))
      (should (equal (alist-get 'workMode task) "Deep"))
      (should (equal (alist-get 'waitUntil task) "<2026-11-11 Wed 09:00>"))
      (should (equal (alist-get 'scheduled task) "<2026-11-11 Wed 10:00>"))
      (should (equal (alist-get 'prerequisites task) '("prereq-a")))
      ;; The dependency target is not a descendant dependency.
      (with-temp-file (expand-file-name "child.org" root)
        (insert "* TODO Child #task\n:PROPERTIES:\n:ID: child\n:END:\n"))
      (should (equal (alist-get 'prerequisites
                                (car (alist-get 'tasks
                                                (lifeos-task-export-test--read output))))
                     '("prereq-a"))))))

(ert-deftest lifeos-task-export-work-mode-inherits-project-default ()
  (with-temp-buffer
    (insert "* Project #project
:PROPERTIES:
:DEFAULT_WORK_MODE: Shallow
:END:
** TODO Child #task
:PROPERTIES:
:ID: child
:WORK_MODE:
:END:
")
    (org-mode)
    (goto-char (point-min))
    (re-search-forward "TODO Child")
    (org-back-to-heading t)
    (should (equal (my/lifeos-task-export--work-mode) "Shallow"))
    (org-entry-put nil "WORK_MODE" "Deep")
    (should (equal (my/lifeos-task-export--work-mode) "Deep"))))

(ert-deftest lifeos-task-export-reads-status-from-verified-disk-bytes ()
  (lifeos-task-export-test--with-acquisition
    ;; The public node summary exposes no :todo, so status must come from the
    ;; verified source bytes rather than from the index.
    (with-temp-file source
      (insert "* DONE Prepare report #task\n:PROPERTIES:\n:ID: id-1\n:END:\n"))
    (my/lifeos-acquire-task-snapshot output root "UTC")
    (let* ((data (lifeos-task-export-test--read output))
           (task (car (alist-get 'tasks data))))
      (should (eq (alist-get 'complete data) t))
      (should (equal (length (alist-get 'tasks data)) 1))
      (should (equal (alist-get 'status task) "complete")))))
