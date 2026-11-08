;;; lifeos-task-export.el --- explicit read-only semantic task export -*- lexical-binding: t; -*-
;; Run in an already initialized Emacs session; NEVER batch-load the live
;; Supertag store for this command. No sync, rescan or LifeOS file writes.
(require 'org)
(require 'cl-lib)
(require 'json)
(require 'subr-x)
(defvar supertag--initialized)
(defconst my/lifeos-task-export-tag-id "f2d7075f-d8a8-45c0-9e44-40270fb9e99d")

(defun my/lifeos-export-task-snapshot (output root zone)
  "Export verified task IDs from initialized Supertag to OUTPUT.
ROOT is the Org vault, ZONE an IANA timezone. OUTPUT must be outside ROOT.
An incomplete export is diagnostic only; absence never means deletion."
  (unless (and (boundp 'supertag--initialized) supertag--initialized
               (fboundp 'supertag-api-query) (fboundp 'supertag-api-node)
               (fboundp 'supertag-dirty-p) (not (supertag-dirty-p)))
    (error "Supertag must already be initialized, clean and expose public API; refusing to load or sync"))
  (let* ((root (file-name-as-directory (file-truename root)))
         (output (expand-file-name output))
         (seen (make-hash-table :test 'equal))
         (tasks nil)
         (issues nil)
         (result (supertag-api-query '(tag "task"))))
    (when (file-in-directory-p output root)
      (error "Snapshot must be outside LifeOS"))
    (when (plist-get result :truncated)
      (error "Supertag query truncated; refusing partial semantic membership"))
    (dolist (summary (plist-get result :nodes))
      (let* ((id (plist-get summary :id))
             (node (and id (condition-case nil (supertag-api-node id) (error nil))))
             (file (and node (plist-get node :file))))
        (condition-case err
            (progn
              (unless (and (stringp id) (stringp file)
                           (not (gethash id seen)) (file-regular-p file)
                           (file-in-directory-p (file-truename file) root)
                           (not (file-symlink-p file))
                           (equal (plist-get node :id) id)
                           (equal (plist-get (plist-get node :properties) :ID) id)
                           (cl-find my/lifeos-task-export-tag-id (plist-get node :tags)
                                    :key (lambda (tag) (plist-get tag :id)) :test #'equal))
                (error "Unverified index identity, membership or source"))
              (puthash id t seen)
              (with-temp-buffer
                (insert-file-contents-literally file)
                (let ((hash (secure-hash 'sha256 (current-buffer)))
                      (found nil)
                      (record nil))
                  (setq-local buffer-file-name file)
                  (org-mode)
                  (org-map-entries
                   (lambda ()
                     (when (equal (org-entry-get nil "ID") id)
                       (setq found (1+ (or found 0)))
                       (let* ((title (org-get-heading t t t t))
                              (todo (org-get-todo-state))
                              (deadline (org-entry-get nil "DEADLINE"))
                              (effort (org-entry-get nil "EFFORT")))
                         (unless (and (equal title (plist-get node :title))
                                      (member todo org-todo-keywords-1))
                           (error "Indexed node differs from disk"))
                         (setq record `((id . ,id) (file . ,(file-relative-name file root))
                                        (fileHash . ,hash)
                                        (membership . ((tagId . ,my/lifeos-task-export-tag-id)
                                                       (via . "supertag-api-query/node")))
                                        (title . ,title)
                                        (status . ,(if (org-entry-is-done-p) "complete" "open"))
                                        (deadline . ,deadline) (effort . ,effort))))))
                   nil 'file)
                  (unless (= (or found 0) 1) (error "Missing or duplicate Org ID"))
                  (push record tasks))))
          (error (push `((id . ,(or id "unknown"))
                         (reason . ,(error-message-string err))) issues)))))
    ;; Public node hash is NOT a file revision; a tag can have changed on disk
    ;; while title/ID still match. Until a public indexed-file fingerprint or
    ;; post-commit sync receipt exists, none of these candidates is trusted.
    (when tasks
      (dolist (task tasks)
        (push `((id . ,(alist-get 'id task))
                (reason . "Indexed membership freshness cannot be proven from public API")) issues))
      (setq tasks nil))
    (push '((id . "whole-scan")
            (reason . "Public API provides no indexed source-file fingerprint or whole-scan freshness proof")) issues)
    ;; Write one atomic diagnostic output only. No source or store writes.
    (let ((temporary (make-temp-file (concat output ".tmp-"))))
      (unwind-protect
          (progn
            (with-temp-file temporary
              (insert (json-encode `((version . 1) (complete . ,(if issues :json-false t))
                                     (zone . ,zone) (tasks . ,(vconcat (nreverse tasks)))
                                     (issues . ,(vconcat (nreverse issues)))))))
            (rename-file temporary output t))
        (when (file-exists-p temporary) (delete-file temporary))))))

(provide 'lifeos-task-export)
