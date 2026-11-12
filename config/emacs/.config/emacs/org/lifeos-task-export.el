;;; lifeos-task-export.el --- explicit read-only semantic task export -*- lexical-binding: t; -*-
;; Run in an already initialized Emacs session; NEVER batch-load the live
;; Supertag store for this command. No LifeOS source writes.
;;
;; The pure export (`my/lifeos-export-task-snapshot') is read-only and
;; fail-closed. The acquisition command (`my/lifeos-acquire-task-snapshot')
;; may run a public full rescan and write Supertag's own store/state, never
;; Org or LifeOS source files. It is the only path that can emit a trusted
;; version 2 snapshot.
(require 'org)
(require 'cl-lib)
(require 'json)
(require 'subr-x)
;; Reuse the existing append-only effort-drawer parser instead of duplicating
;; episode/correction attribution in the exporter.
(require 'lifeos-planning)
(require 'lifeos-schedule)
(declare-function my/lifeos-effort-state "lifeos-planning" ())
(defvar supertag--initialized nil)
(declare-function supertag-api-query "supertag-api" (query &optional limit))
(declare-function supertag-api-node "supertag-api" (node-id))
(declare-function supertag-dirty-p "supertag-core-persistence" ())
(declare-function supertag-scan-sync-directories "supertag-services-sync" (&optional all-files-p))
(declare-function supertag-sync-full-rescan "supertag-services-sync" ())
(defconst my/lifeos-task-export-tag-id "f2d7075f-d8a8-45c0-9e44-40270fb9e99d")
(defconst my/lifeos-task-export-project-tag-id "1988054a-d048-49ce-bd20-4eb4f9a6f458"
  "Stable `#project` tag id. Deadline-bearing projects are deadline evidence,
even though they are not task demand and carry no effort.")

(defun my/lifeos-task-export--dependency-targets ()
  "Return depends-on target IDs from the current heading's own body.
Descendant headings are excluded; dependency semantics belong to the task
entry, not its children."
  (save-excursion
    (org-back-to-heading t)
    (forward-line 1)
    (let ((start (point))
          (end (save-excursion
                 (if (re-search-forward "^\\*+ " nil t)
                     (match-beginning 0)
                   (point-max))))
          targets)
      (save-restriction
        (narrow-to-region start end)
        (goto-char start)
        (while (re-search-forward "\\[\\[depends-on:\\([^]]+\\)\\]" nil t)
          (push (match-string-no-properties 1) targets)))
      (nreverse targets))))

(defun my/lifeos-task-export--work-mode ()
  "Return the task's explicit work mode, falling back to the project default.
Empty property values are treated as unset, matching the groomed scaffold."
  (let ((own (org-entry-get nil "WORK_MODE")))
    (if (and own (not (string-empty-p own)))
        own
      (let ((default (org-entry-get nil "DEFAULT_WORK_MODE" t)))
        (and default (not (string-empty-p default)) default)))))

(defun my/lifeos-task-export--effort-evidence ()
  "Return read-only effort evidence for the task at point.
The existing `my/lifeos-effort-state' parser owns episode/correction and clock
attribution. Its clock conversion is machine-local, so the evidence records
that basis and is not trusted calendar coverage. Record-integrity problems are
exported as `valid: false' with the issue list; the surrounding task bytes are
still verified independently."
  (condition-case err
      (let* ((state (my/lifeos-effort-state))
             (valid (and (plist-get state :valid-p) t)))
        `((valid . ,(if valid t :json-false))
          (clockZoneBasis . "machine-local")
          ;; A record-integrity failure withholds every derived fact; the task
          ;; itself may still be verified, but its effort is unknown.
          (episodeId . ,(and valid (plist-get state :episode-id)))
          (episodeStartedAt . ,(and valid (plist-get state :episode-started-at)))
          (episodes . ,(vconcat
                        (when valid
                          (mapcar (lambda (episode)
                                    `((id . ,(plist-get episode :id))
                                      (start . ,(plist-get episode :start))))
                                  (plist-get state :episodes)))))
          (corrections . ,(vconcat
                           (when valid
                             (mapcar (lambda (correction)
                                       `((correctionId . ,(plist-get correction :correction-id))
                                         (episodeId . ,(plist-get correction :episode-id))
                                         (effectiveAt . ,(plist-get correction :effective-at))
                                         (remainingMinutes . ,(plist-get correction :remaining-minutes))
                                         (revision . ,(plist-get correction :revision))))
                                     (plist-get state :corrections)))))
          (clocks . ,(vconcat
                      (when valid
                        (mapcar (lambda (clock)
                                  `((clockId . ,(plist-get clock :clock-id))
                                    (episodeId . ,(plist-get clock :episode-id))
                                    (startedAt . ,(plist-get clock :started-at))
                                    (endedAt . ,(plist-get clock :ended-at))))
                                (plist-get state :clocks)))))
          (issues . ,(vconcat
                      (mapcar (lambda (issue)
                                `((code . ,(symbol-name (plist-get issue :code)))
                                  (detail . ,(plist-get issue :detail))))
                              (plist-get state :issues))))
          (provenance . ,(symbol-name (plist-get state :effort-provenance)))))
    (error
     `((valid . :json-false)
       (clockZoneBasis . "machine-local")
       (episodeId . nil)
       (episodeStartedAt . nil)
       (episodes . [])
       (corrections . [])
       (clocks . [])
       (issues . [((code . "effort-state-failed")
                   (detail . ,(error-message-string err)))])
       (provenance . "missing")))))

(defun my/lifeos-task-export--instant (minute)
  "Format epoch MINUTE as a UTC instant for the coordinator boundary."
  (format-time-string "%Y-%m-%dT%H:%M:%SZ" (seconds-to-time (* minute 60)) t))

(defun my/lifeos-task-export--schedule-value
    (present file hash plan-id fingerprint accepted issues &optional blocks)
  "Return Accepted schedule evidence for the coordinator.
PRESENT covers the planning file, not merely the Accepted subtree. VALID is
derived from ISSUES. Blocks are withheld whenever ISSUES is non-empty."
  `((present . ,(if present t :json-false))
    (valid . ,(if issues :json-false t))
    (planId . ,plan-id)
    (sourceFingerprint . ,fingerprint)
    (acceptedAt . ,accepted)
    (file . ,file)
    (fileHash . ,hash)
    (issues . ,(vconcat issues))
    (blocks . ,(vconcat (unless issues blocks)))))

(defun my/lifeos-task-export--schedule-from-buffer (buffer relative file-hash tasks)
  "Return Accepted schedule evidence parsed from BUFFER.
RELATIVE and FILE-HASH identify the planning file within the acquisition root.
TASKS are the verified task entries in the same snapshot."
  (let* ((plan (my/lifeos-schedule-parse-current-plan buffer))
         (metadata (plist-get plan :metadata))
         (plan-id (cdr (assoc "LIFEOS_PLAN_ID" metadata)))
         (fingerprint (cdr (assoc "LIFEOS_PLAN_SOURCE_FINGERPRINT" metadata)))
         (accepted-raw (cdr (assoc "LIFEOS_PLAN_ACCEPTED_AT" metadata)))
         (accepted (and accepted-raw
                        (format-time-string
                         "%Y-%m-%dT%H:%M:%SZ" (date-to-time accepted-raw) t))))
    (cond
     ((not (plist-get plan :present-p))
      ;; A planning file with no Accepted subtree is a valid empty plan.
      (my/lifeos-task-export--schedule-value
       t relative file-hash nil nil nil nil nil))
     ((not (plist-get plan :valid-p))
      (my/lifeos-task-export--schedule-value
       t relative file-hash plan-id fingerprint accepted
       (or (plist-get plan :issues) (list "accepted schedule is invalid"))))
     (t
      (let* ((task-ids (mapcar (lambda (task) (alist-get 'id task)) tasks))
             (blocks
              (cl-loop for block in (plist-get plan :blocks)
                       when (eq (plist-get block :kind) 'task)
                       collect `((blockId . ,(plist-get block :id))
                                 (taskId . ,(plist-get block :task-id))
                                 (start . ,(my/lifeos-task-export--instant
                                            (plist-get block :start)))
                                 (end . ,(my/lifeos-task-export--instant
                                          (plist-get block :end)))
                                 (minutes . ,(plist-get block :minutes)))))
             (unknown (seq-filter
                       (lambda (block)
                         (not (member (alist-get 'taskId block) task-ids)))
                       blocks)))
        (if unknown
            (my/lifeos-task-export--schedule-value
             t relative file-hash plan-id fingerprint accepted
             (mapcar (lambda (block)
                       (format "accepted block %s references unknown task %s"
                               (alist-get 'blockId block)
                               (alist-get 'taskId block)))
                     unknown))
          (my/lifeos-task-export--schedule-value
           t relative file-hash plan-id fingerprint accepted nil blocks)))))))

(defun my/lifeos-task-export--schedule (root tasks)
  "Return read-only Accepted schedule evidence for ROOT and exported TASKS.
The Emacs parser owns plan structure; the coordinator re-verifies FILEHASH and
block/task references. A planning file without an Accepted subtree is a valid
empty plan. No file is valid absence. An invalid plan keeps its identity/issues
but never carries blocks."
  (let ((file (my/lifeos-schedule--planning-file)))
    (cond
     ((not (file-exists-p file))
      (my/lifeos-task-export--schedule-value nil nil nil nil nil nil nil))
     ((not (file-in-directory-p (file-truename file) root))
      (my/lifeos-task-export--schedule-value
       t nil nil nil nil nil (list "planning file is outside acquisition root")))
     (t
      ;; `org-map-entries' only scans a buffer as a file when it has a
      ;; buffer-file-name. Use a disposable, hook-free buffer and clear the
      ;; modified flag before killing it so Emacs never offers to save the vault.
      (let ((buffer (generate-new-buffer " *lifeos-schedule-parse*"))
            (relative (file-relative-name (file-truename file) root)))
        (unwind-protect
            (with-current-buffer buffer
              (insert-file-contents-literally file)
              (setq-local buffer-file-name file)
              (let ((org-mode-hook nil)) (org-mode))
              (my/lifeos-task-export--schedule-from-buffer
               buffer relative (secure-hash 'sha256 (current-buffer)) tasks))
          (when (buffer-live-p buffer)
            (with-current-buffer buffer
              (set-buffer-modified-p nil))
            (kill-buffer buffer))))))))

(defconst my/lifeos-task-export-fingerprint-version "v2"
  "Version prefix for `my/lifeos-task-export--fingerprint' output.
Bumped when the exported semantic query changes so an older task-only
snapshot is rescanned instead of reused.")
(defconst my/lifeos-task-export-snapshot-version 2
  "Version of the trusted snapshot envelope produced with a receipt.")

(defgroup my/lifeos-task-acquisition nil
  "Live LifeOS task acquisition exported from Supertag."
  :group 'org)

(defcustom my/lifeos-task-acquisition-output nil
  "Absolute path of the exported task snapshot.
Must be outside the Org vault. Acquisition is inactive until this, the root
and the zone are all configured."
  :type '(choice (const :tag "Unconfigured" nil) file)
  :group 'my/lifeos-task-acquisition)

(defcustom my/lifeos-task-acquisition-root nil
  "Org vault root that acquisition exports.
Acquisition refuses any SuperTag file outside this directory."
  :type '(choice (const :tag "Unconfigured" nil) directory)
  :group 'my/lifeos-task-acquisition)

(defcustom my/lifeos-task-acquisition-zone nil
  "IANA timezone name recorded in the exported snapshot."
  :type '(choice (const :tag "Unconfigured" nil) string)
  :group 'my/lifeos-task-acquisition)

(defcustom my/lifeos-task-acquisition-auto-start t
  "When non-nil, start the acquisition timer after Emacs startup if configured."
  :type 'boolean
  :group 'my/lifeos-task-acquisition)

(defcustom my/lifeos-task-acquisition-interval 60
  "Seconds between acquisition heartbeats."
  :type 'number
  :group 'my/lifeos-task-acquisition)

(defvar my/lifeos-task-acquisition--timer nil
  "Repeating acquisition timer, or nil when stopped.")

(defvar my/lifeos-task-acquisition--pause-reason nil
  "Last reported reason acquisition could not run, for message throttling.")

(defun my/lifeos-task-export--not-ready-reason ()
  "Return why the Supertag session cannot be acquired from, or nil when ready."
  (cond
   ((not (and (boundp 'supertag--initialized) supertag--initialized))
    "Supertag is not initialized")
   ((not (fboundp 'supertag-api-query)) "Supertag public query API is unavailable")
   ((not (fboundp 'supertag-api-node)) "Supertag public node API is unavailable")
   ((not (fboundp 'supertag-dirty-p)) "Supertag dirty-state API is unavailable")
   ((supertag-dirty-p) "Supertag has unsaved store changes")
   (t nil)))

(defun my/lifeos-task-export--session-ready-p ()
  "Return non-nil when Supertag is initialized, clean and public."
  (null (my/lifeos-task-export--not-ready-reason)))

(defun my/lifeos-task-acquisition--pause (reason)
  "Report REASON once until acquisition resumes."
  (unless (equal reason my/lifeos-task-acquisition--pause-reason)
    (setq my/lifeos-task-acquisition--pause-reason reason)
    (message "LifeOS task acquisition paused: %s" reason)))

(defun my/lifeos-task-export--require-session ()
  "Signal unless Supertag is initialized, clean and exposes the public API."
  (when-let* ((reason (my/lifeos-task-export--not-ready-reason)))
    (error "Refusing export: %s" reason)))

(defun my/lifeos-task-export--iso (time)
  "Return TIME as an ISO 8601 UTC instant string."
  (format-time-string "%Y-%m-%dT%H:%M:%SZ" time t))

(defun my/lifeos-task-export--new-id (time)
  "Return a fresh acquisition id for TIME."
  (format "%s-%s"
          (format-time-string "%Y%m%dT%H%M%SZ" time t)
          (substring (secure-hash 'sha1 (format "%s-%s" (float-time time) (random))) 0 12)))

(defun my/lifeos-task-export--scan-files (root)
  "Return the sorted in-scope Org files under ROOT.
Uses the public `supertag-scan-sync-directories' enumeration and refuses
anything that is not a regular, non-symlink file inside ROOT."
  (unless (fboundp 'supertag-scan-sync-directories)
    (error "Supertag must expose public `supertag-scan-sync-directories'"))
  (let ((files (sort (delete-dups (copy-sequence (supertag-scan-sync-directories t)))
                     #'string<)))
    (dolist (file files)
      (unless (and (stringp file) (file-regular-p file)
                   (not (file-symlink-p file))
                   (file-in-directory-p (file-truename file) root))
        (error "Supertag returned an out-of-vault or non-regular file: %S" file)))
    files))

(defun my/lifeos-task-export--describe-files (files)
  "Return (FILE MTIME SIZE) descriptions for FILES."
  (mapcar (lambda (file)
            (let ((attrs (file-attributes file)))
              (unless attrs
                (error "In-scope file disappeared during acquisition: %s" file))
              (list file (float-time (file-attribute-modification-time attrs))
                    (file-attribute-size attrs))))
          files))

(defun my/lifeos-task-export--fingerprint (descriptions)
  "Return a fingerprint over DESCRIPTIONS of paths, mtimes and sizes."
  (concat my/lifeos-task-export-fingerprint-version ":"
          (secure-hash
           'sha256
           (mapconcat (lambda (entry)
                        (format "%s\0%.6f\0%d\n"
                                (nth 0 entry) (nth 1 entry) (nth 2 entry)))
                      descriptions ""))))

(defun my/lifeos-task-export--assert-not-modified-since (descriptions started-at)
  "Signal if any file in DESCRIPTIONS was modified after STARTED-AT."
  (dolist (entry descriptions)
    (when (> (nth 1 entry) started-at)
      (error "In-scope file changed during acquisition: %s" (nth 0 entry)))))

(defun my/lifeos-task-export--read-snapshot (output)
  "Return the decoded snapshot at OUTPUT, or nil when absent or invalid."
  (when (file-readable-p output)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents output)
          (json-parse-string (buffer-string)
                             :object-type 'alist :array-type 'list))
      (error nil))))

(defun my/lifeos-task-export--field (key alist)
  "Return the value of KEY in decoded JSON ALIST."
  (let ((entry (or (assoc key alist) (assoc (symbol-name key) alist))))
    (cdr entry)))

(defun my/lifeos-task-export--reusable-p (previous fingerprint zone)
  "Return non-nil when PREVIOUS proves a complete rescan over FINGERPRINT.
ZONE must match; an unknown or version 1 snapshot is never reused."
  (and (listp previous)
       (equal (my/lifeos-task-export--field 'version previous)
              my/lifeos-task-export-snapshot-version)
       (equal (my/lifeos-task-export--field 'scanStatus previous) "complete")
       (equal (my/lifeos-task-export--field 'zone previous) zone)
       (equal (my/lifeos-task-export--field 'fileSetFingerprint previous) fingerprint)
       (stringp (my/lifeos-task-export--field 'acquisitionId previous))
       (stringp (my/lifeos-task-export--field 'scanStartedAt previous))
       (stringp (my/lifeos-task-export--field 'scanCompletedAt previous))))

(defun my/lifeos-task-export--reused-receipt (previous fingerprint exported-at)
  "Return a receipt reusing PREVIOUS's complete rescan over FINGERPRINT."
  (list :acquisition-id (my/lifeos-task-export--field 'acquisitionId previous)
        :exported-at exported-at
        :scan-started-at (my/lifeos-task-export--field 'scanStartedAt previous)
        :scan-completed-at (my/lifeos-task-export--field 'scanCompletedAt previous)
        :scan-status "complete"
        :files-discovered (my/lifeos-task-export--field 'filesDiscovered previous)
        :files-processed (my/lifeos-task-export--field 'filesProcessed previous)
        :file-set-fingerprint fingerprint))

(defun my/lifeos-task-export--rescan (expected-count)
  "Run one public full rescan and require a complete report over EXPECTED-COUNT."
  (unless (fboundp 'supertag-sync-full-rescan)
    (error "Supertag must expose public `supertag-sync-full-rescan'"))
  (let* ((report (supertag-sync-full-rescan))
         (status (plist-get report :status))
         (discovered (plist-get report :files-discovered))
         (processed (plist-get report :files-processed)))
    (unless (eq status 'complete)
      (error "Supertag full rescan did not complete: %S" status))
    (unless (and (integerp discovered) (integerp processed)
                 (= discovered processed)
                 (= discovered expected-count))
      (error "Supertag full rescan counts disagree: discovered=%S processed=%S expected=%S"
             discovered processed expected-count))
    report))

(defun my/lifeos-task-export--ensure-parent (output)
  "Create OUTPUT's parent directory when missing."
  (let ((parent (file-name-directory output)))
    (unless (file-directory-p parent) (make-directory parent t))))

(defun my/lifeos-task-export--write (output data)
  "Write DATA as JSON to OUTPUT atomically."
  (let ((temporary (make-temp-file (concat output ".tmp-")))
        (coding-system-for-write 'utf-8-unix))
    (unwind-protect
        (progn
          ;; Write the string directly. `with-temp-file' kills a buffer that
          ;; `write-region' leaves modified, which makes Emacs 31 prompt via
          ;; `kill-buffer--possibly-save' inside a timer/acquisition.
          (write-region (json-encode data) nil temporary nil 'silent)
          (rename-file temporary output t))
      (when (file-exists-p temporary) (delete-file temporary)))))

(defun my/lifeos-task-export--v1 (zone tasks issues complete)
  "Return a version 1 administrative snapshot."
  `((version . 1)
    (complete . ,(if complete t :json-false))
    (zone . ,zone)
    (tasks . ,(vconcat tasks))
    (issues . ,(vconcat issues))))

(defun my/lifeos-task-export--v2 (receipt zone tasks issues complete schedule)
  "Return a version 2 acquisition snapshot built from RECEIPT and SCHEDULE."
  `((version . ,my/lifeos-task-export-snapshot-version)
    (acquisitionId . ,(plist-get receipt :acquisition-id))
    (exportedAt . ,(plist-get receipt :exported-at))
    (zone . ,zone)
    (scanStartedAt . ,(plist-get receipt :scan-started-at))
    (scanCompletedAt . ,(plist-get receipt :scan-completed-at))
    (scanStatus . ,(plist-get receipt :scan-status))
    (filesDiscovered . ,(plist-get receipt :files-discovered))
    (filesProcessed . ,(plist-get receipt :files-processed))
    (fileSetFingerprint . ,(plist-get receipt :file-set-fingerprint))
    (complete . ,(if complete t :json-false))
    (tasks . ,(vconcat tasks))
    (issues . ,(vconcat issues))
    (schedule . ,schedule)))

(defun my/lifeos-export-task-snapshot (output root zone &optional receipt)
  "Export verified task IDs from initialized Supertag to OUTPUT.
ROOT is the Org vault, ZONE an IANA timezone. OUTPUT must be outside ROOT.
RECEIPT, when non-nil, is a plist proving a fresh complete public rescan; it
is required for a trusted version 2 snapshot. Without RECEIPT this writes a
version 1 administrative diagnostic, never a live judgment. An incomplete
export is diagnostic only; absence never means deletion."
  (my/lifeos-task-export--require-session)
  (let* ((root (file-name-as-directory (file-truename root)))
         (output (expand-file-name output))
         (seen (make-hash-table :test 'equal))
         (tasks nil)
         (issues nil)
         (result (supertag-api-query '(or (tag "task") (tag "project")))))
    (when (file-in-directory-p output root)
      (error "Snapshot must be outside LifeOS"))
    (when (plist-get result :truncated)
      (error "Supertag query truncated; refusing partial semantic membership"))
    (dolist (summary (plist-get result :nodes))
      (let* ((id (plist-get summary :id))
             (node (and id (condition-case nil (supertag-api-node id) (error nil))))
             (file (and node (plist-get node :file)))
             (tags (and node (plist-get node :tags)))
             (kind (cond
                    ((cl-find my/lifeos-task-export-tag-id tags
                              :key (lambda (tag) (plist-get tag :id)) :test #'equal) "task")
                    ((cl-find my/lifeos-task-export-project-tag-id tags
                              :key (lambda (tag) (plist-get tag :id)) :test #'equal) "project")
                    (t nil))))
        (condition-case err
            (progn
              (unless (and (stringp id) (stringp file) kind
                           (not (gethash id seen)) (file-regular-p file)
                           (file-in-directory-p (file-truename file) root)
                           (not (file-symlink-p file))
                           (equal (plist-get node :id) id))
                (error "Unverified index identity, membership or source"))
              (puthash id t seen)
              ;; Parse in a disposable buffer without the user's Org mode
              ;; hooks. Hooks such as org-roam/org-indent can modify this
              ;; buffer or prompt, which must never happen inside acquisition.
              (let ((buffer (generate-new-buffer " *lifeos-task-parse*")))
                (unwind-protect
                    (with-current-buffer buffer
                      (insert-file-contents-literally file)
                      (let ((hash (secure-hash 'sha256 (current-buffer)))
                            (found nil)
                            (record nil))
                        (setq-local buffer-file-name file)
                        (let ((org-mode-hook nil)) (org-mode))
                        (org-map-entries
                         (lambda ()
                           (when (equal (org-entry-get nil "ID") id)
                             (setq found (1+ (or found 0)))
                             (let* ((todo (org-get-todo-state))
                                    (deadline (org-entry-get nil "DEADLINE"))
                                    ;; Projects are deadline evidence, not task
                                    ;; demand. Never borrow PROJECT_EFFORT or an
                                    ;; incidental EFFORT as task demand.
                                    (effort (and (equal kind "task")
                                                 (org-entry-get nil "EFFORT"))))
                               ;; Supertag's public :title is cleaned of inline #tags,
                               ;; so exact title equality is not an invariant and
                               ;; stripping them here would reimplement its parser.
                               ;; The public node shape also exposes no :todo, so
                               ;; status cannot be compared with the index.
                               ;; Identity is bound by node id, file and tag; the
                               ;; on-disk ID must be unique and status is read
                               ;; from these verified bytes.
                               (unless (or (null todo)
                                           (member todo org-todo-keywords-1))
                                 (error "Disk todo state is not a known keyword"))
                               (setq record `((id . ,id) (file . ,(file-relative-name file root))
                                              (fileHash . ,hash)
                                              (membership . ((tagId . ,(if (equal kind "project")
                                                                           my/lifeos-task-export-project-tag-id
                                                                         my/lifeos-task-export-tag-id))
                                                             (via . "supertag-api-query/node")))
                                              (kind . ,kind)
                                              (title . ,(plist-get node :title))
                                              (status . ,(if (org-entry-is-done-p) "complete" "open"))
                                              (deadline . ,deadline) (effort . ,effort)
                                              ;; A03 policy facts. WORK_MODE is
                                              ;; task-local; DEFAULT_WORK_MODE is
                                              ;; inherited from the nearest
                                              ;; project ancestor.
                                              (workMode . ,(my/lifeos-task-export--work-mode))
                                              (waitUntil . ,(org-entry-get nil "WAIT_UNTIL"))
                                              (scheduled . ,(org-entry-get nil "SCHEDULED"))
                                              (prerequisites . ,(vconcat (my/lifeos-task-export--dependency-targets)))
                                              ;; Correction-anchored effort input is task-only:
                                              ;; a project deadline never borrows project effort.
                                              ,@(when (equal kind "task")
                                                  `((effortState . ,(my/lifeos-task-export--effort-evidence)))))))))
                         nil 'file)
                        (unless (= (or found 0) 1) (error "Missing or duplicate Org ID"))
                        (push record tasks)))
                  ;; `org-mode' marks the buffer modified even though its text is
                  ;; unchanged. Clear the flag before killing: Emacs 31 otherwise
                  ;; asks via `kill-buffer--possibly-save' (yes/no/save), which
                  ;; blocks the live server and offers to write this disposable
                  ;; buffer over the vault file.
                  (with-current-buffer buffer
                    (set-buffer-modified-p nil))
                  (kill-buffer buffer))))
          (error (push `((id . ,(or id "unknown"))
                         (reason . ,(error-message-string err))) issues)))))
    (setq tasks (nreverse tasks))
    (setq issues (nreverse issues))
    (let ((complete (and receipt (null issues))))
      (unless receipt
        ;; Public node hash is NOT a file revision; a tag can have changed on
        ;; disk while title/ID still match. Without a rescan receipt no
        ;; candidate is trusted, so keep the administrative diagnostic only.
        (when tasks
          (dolist (task tasks)
            (push `((id . ,(alist-get 'id task))
                    (reason . "Indexed membership freshness cannot be proven from public API"))
                  issues))
          (setq tasks nil))
        (push '((id . "whole-scan")
                (reason . "Public API provides no indexed source-file fingerprint or whole-scan freshness proof"))
              issues)
        (setq issues (nreverse issues)))
      (when (and receipt (not complete))
        ;; A partial v2 export freezes evaluation; withhold the untrusted tasks.
        (setq tasks nil))
      (my/lifeos-task-export--write
       output
       (if receipt
           (my/lifeos-task-export--v2
            receipt zone tasks issues complete
            (my/lifeos-task-export--schedule root tasks))
         (my/lifeos-task-export--v1 zone tasks issues (and (null issues) t)))))))

(defun my/lifeos-acquire-task-snapshot (output root zone)
  "Acquire a fresh, complete Supertag rescan receipt and export OUTPUT.
OUTPUT must be outside ROOT. Reuses the previous version 2 rescan only while
the in-scope file/path/mtime/size fingerprint is unchanged. Aborts without
overwriting the last good snapshot when the file set changes mid-acquisition
or any in-scope file was modified after this call started."
  (my/lifeos-task-export--require-session)
  (let* ((root (file-name-as-directory (file-truename root)))
         (output (expand-file-name output))
         (started-at (float-time))
         (before-files (my/lifeos-task-export--scan-files root))
         (before (my/lifeos-task-export--describe-files before-files))
         (fingerprint (my/lifeos-task-export--fingerprint before))
         (previous (my/lifeos-task-export--read-snapshot output))
         (reused (and (my/lifeos-task-export--reusable-p previous fingerprint zone)
                      previous))
         (now (float-time))
         (receipt (if reused
                      (my/lifeos-task-export--reused-receipt
                       reused fingerprint (my/lifeos-task-export--iso now))
                    (progn
                      (my/lifeos-task-export--rescan (length before-files))
                      (list :acquisition-id (my/lifeos-task-export--new-id now)
                            :exported-at (my/lifeos-task-export--iso now)
                            :scan-started-at (my/lifeos-task-export--iso started-at)
                            :scan-completed-at (my/lifeos-task-export--iso (float-time))
                            :scan-status "complete"
                            :files-discovered (length before-files)
                            :files-processed (length before-files)
                            :file-set-fingerprint fingerprint)))))
    (when (file-in-directory-p output root)
      (error "Snapshot must be outside LifeOS"))
    (let* ((after-files (my/lifeos-task-export--scan-files root))
           (after (my/lifeos-task-export--describe-files after-files)))
      (unless (equal before-files after-files)
        (error "In-scope file set changed during acquisition; keeping last snapshot"))
      (my/lifeos-task-export--assert-not-modified-since after started-at)
      (unless (equal (my/lifeos-task-export--fingerprint after) fingerprint)
        (error "In-scope files changed during acquisition; keeping last snapshot")))
    (my/lifeos-task-export--ensure-parent output)
    (my/lifeos-export-task-snapshot output root zone receipt)
    receipt))

(defun my/lifeos-task-acquisition-configured-p ()
  "Return non-nil when output, root and zone are all configured."
  (and (stringp my/lifeos-task-acquisition-output)
       (not (string-empty-p my/lifeos-task-acquisition-output))
       (stringp my/lifeos-task-acquisition-root)
       (not (string-empty-p my/lifeos-task-acquisition-root))
       (stringp my/lifeos-task-acquisition-zone)
       (not (string-empty-p my/lifeos-task-acquisition-zone))))

(defun my/lifeos-task-acquisition-tick ()
  "Run one acquisition when configured and Supertag is ready.
Report a pause reason once per distinct reason. The coordinator freezes on a
missing heartbeat, so a stalled acquisition is visible as staleness rather than
silently keeping old facts alive."
  (when (my/lifeos-task-acquisition-configured-p)
    (let ((reason (condition-case err
                      (my/lifeos-task-export--not-ready-reason)
                    (error (format "readiness check failed: %s"
                                   (error-message-string err))))))
      (if reason
          (my/lifeos-task-acquisition--pause reason)
        (condition-case err
            (progn
              (my/lifeos-acquire-task-snapshot
               my/lifeos-task-acquisition-output
               my/lifeos-task-acquisition-root
               my/lifeos-task-acquisition-zone)
              (setq my/lifeos-task-acquisition--pause-reason nil))
          (error
           (my/lifeos-task-acquisition--pause
            (format "acquisition failed: %s" (error-message-string err)))))))))

(defun my/lifeos-task-acquisition-start ()
  "Start the repeating acquisition timer."
  (interactive)
  (unless (my/lifeos-task-acquisition-configured-p)
    (user-error "Set my/lifeos-task-acquisition-output, -root and -zone first"))
  (unless (and (numberp my/lifeos-task-acquisition-interval)
               (> my/lifeos-task-acquisition-interval 0))
    (user-error "my/lifeos-task-acquisition-interval must be a positive number"))
  (my/lifeos-task-acquisition-stop)
  (setq my/lifeos-task-acquisition--timer
        (run-with-timer 0 my/lifeos-task-acquisition-interval
                        #'my/lifeos-task-acquisition-tick))
  my/lifeos-task-acquisition--timer)

(defun my/lifeos-task-acquisition-stop ()
  "Stop the repeating acquisition timer."
  (interactive)
  (when (timerp my/lifeos-task-acquisition--timer)
    (cancel-timer my/lifeos-task-acquisition--timer))
  (setq my/lifeos-task-acquisition--timer nil)
  (setq my/lifeos-task-acquisition--pause-reason nil))

(defun my/lifeos-task-acquisition-maybe-start ()
  "Start acquisition when enabled, configured and not already running."
  (when (and my/lifeos-task-acquisition-auto-start
             (my/lifeos-task-acquisition-configured-p)
             (not (timerp my/lifeos-task-acquisition--timer)))
    (my/lifeos-task-acquisition-start)))

(if (bound-and-true-p after-init-time)
    (my/lifeos-task-acquisition-maybe-start)
  (when my/lifeos-task-acquisition-auto-start
    (add-hook 'emacs-startup-hook #'my/lifeos-task-acquisition-maybe-start 90)))

(provide 'lifeos-task-export)
;;; lifeos-task-export.el ends here
