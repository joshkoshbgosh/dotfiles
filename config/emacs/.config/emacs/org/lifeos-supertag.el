;; -*- lexical-binding: t -*-
;;; org/lifeos-supertag.el --- LifeOS Semantic Tag identities

(require 'subr-x)

(defvar supertag--initialized)
(defvar supertag-data-directory)

(defconst my/lifeos-supertag-projection-version "1"
  "Version of the canonical-tag projection contract.")

(defconst my/lifeos-canonical-supertags
  '(("task" . "f2d7075f-d8a8-45c0-9e44-40270fb9e99d")
    ("project" . "1988054a-d048-49ce-bd20-4eb4f9a6f458")
    ("week" . "8036d3c9-a177-4643-afc9-737a19591d98"))
  "Canonical Supertag names and stable IDs used by LifeOS.")

(defun my/lifeos--supertag-projection-stamp-file ()
  "Return the file recording a successful canonical-tag projection rebuild."
  (expand-file-name "lifeos-canonical-projections"
                    supertag-data-directory))

(defun my/lifeos--supertag-projections-current-p ()
  "Return non-nil when canonical-tag projections were rebuilt successfully."
  (let ((file (my/lifeos--supertag-projection-stamp-file)))
    (and (file-readable-p file)
         (string-equal
          (string-trim
           (with-temp-buffer
             (insert-file-contents file)
             (buffer-string)))
          my/lifeos-supertag-projection-version))))

(defun my/lifeos--write-supertag-projection-stamp ()
  "Record a successful canonical-tag projection rebuild."
  (with-temp-file (my/lifeos--supertag-projection-stamp-file)
    (insert my/lifeos-supertag-projection-version "\n")))

(defun my/lifeos--supertag-preflight ()
  "Return missing canonical tags after validating existing identities."
  (let (missing)
    (dolist (entry my/lifeos-canonical-supertags (nreverse missing))
      (pcase-let* ((`(,name . ,expected-id) entry)
                   (resolved-id (supertag-tag-resolve-occurrence name))
                   (tag-at-id (supertag-tag-get expected-id)))
        (cond
         ((and resolved-id (not (equal resolved-id expected-id)))
          (user-error "Canonical tag '%s' resolves to %s, expected %s"
                      name resolved-id expected-id))
         ((and tag-at-id
               (not (equal (plist-get tag-at-id :name) name)))
          (user-error "Canonical tag ID %s belongs to '%s', expected '%s'"
                      expected-id (plist-get tag-at-id :name) name))
         ((and resolved-id (null tag-at-id))
          (error "Canonical tag '%s' resolves to missing entity %s"
                 name expected-id))
         ((and (null resolved-id) tag-at-id)
          (error "Canonical tag '%s' exists at %s but does not resolve"
                 name expected-id))
         ((null resolved-id)
          (push entry missing)))))))

(defun my/lifeos-ensure-canonical-supertags (&optional force-rescan)
  "Ensure canonical LifeOS tags and rescan when needed.

With FORCE-RESCAN non-nil, rebuild projections even when no tag was created."
  (interactive "P")
  (unless (and (boundp 'supertag--initialized) supertag--initialized)
    (user-error "Supertag must be initialized before registering LifeOS tags"))
  (let* ((missing (my/lifeos--supertag-preflight))
         (rescan-needed (or force-rescan
                            missing
                            (not (my/lifeos--supertag-projections-current-p))))
         created
         report)
    (dolist (entry missing)
      (pcase-let ((`(,name . ,id) entry))
        (let ((tag (supertag-tag-create (list :id id :name name))))
          (unless (equal (plist-get tag :id) id)
            (error "Supertag created '%s' with unexpected ID %s"
                   name (plist-get tag :id)))
          (push name created))))
    (when created
      (supertag-save-store)
      (when (supertag-dirty-p)
        (error "Canonical LifeOS tags could not be persisted")))
    (when rescan-needed
      (setq report (supertag-sync-full-rescan))
      (unless (eq (plist-get report :status) 'complete)
        (error "LifeOS Supertag rescan did not complete: %S" report))
      (when (supertag-dirty-p)
        (error "LifeOS Supertag projections could not be persisted"))
      (my/lifeos--write-supertag-projection-stamp))
    (when (my/lifeos--supertag-preflight)
      (error "Canonical LifeOS tags are still missing after registration"))
    (setq created (nreverse created))
    (let ((result (list :created created
                        :rescanned (and report t)
                        :report report
                        :tags (copy-tree my/lifeos-canonical-supertags))))
      (when (called-interactively-p 'interactive)
        (message "LifeOS tags verified%s%s"
                 (if created
                     (format "; created %s" (string-join created ", "))
                   "")
                 (if report "; projections rescanned" "")))
      result)))

(defun my/lifeos-enable-supertag-save-sync ()
  "Install Supertag save synchronization in all open Org buffers."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (supertag-sync-setup-realtime-hooks)))))

(defun my/lifeos-initialize-canonical-supertags ()
  "Verify LifeOS Semantic Tags after Supertag initialization."
  (my/lifeos-enable-supertag-save-sync)
  (condition-case err
      (my/lifeos-ensure-canonical-supertags)
    (error
     (display-warning
      'lifeos
      (format "Canonical Supertag setup failed: %s" (error-message-string err))
      :error))))

(provide 'lifeos-supertag)
