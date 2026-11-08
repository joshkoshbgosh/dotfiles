;; -*- lexical-binding: t -*-
;;; org/org-gcal.el --- Google Calendar import for LifeOS

(require 'auth-source)
(require 'json)
(require 'org)
(require 'seq)
(require 'subr-x)

(defconst my/org-gcal-calendar-file
  (expand-file-name "calendar.org" org-directory))

(defcustom my/org-gcal-credentials-file
  (expand-file-name "gogcli/credentials.json" (or (getenv "XDG_CONFIG_HOME")
                                                   "~/.config"))
  "Google Desktop OAuth client credentials used by org-gcal."
  :type 'file)

(defvar my/org-gcal-calendar-role-alist nil
  "Calendar IDs mapped to canonical roles after authentication is configured.")

(defvar my/org-gcal-fetch-timer nil
  "Timer used for periodic Google Calendar imports.")

(defvar my/org-gcal-fetch-in-progress nil
  "Non-nil while a Google Calendar import is running.")

<<<<<<< HEAD
(defvar my/org-gcal-configured-p nil
  "Non-nil after org-gcal authentication settings are loaded this session.")

(defvar my/org-gcal-last-poll-error nil
  "Most recent background calendar polling error, or nil.")

=======
>>>>>>> c638f20 (update)
(defvar my/org-gcal-last-successful-fetch-time nil
  "Time of the latest org-gcal fetch that completed successfully.")

(defvar my/org-gcal-calendar-coverage-end nil
  "Verified exclusive coverage end; nil until recurrence completeness is proven.")

(defvar org-gcal-down-days 60
  "Future days requested from org-gcal; declared here for pre-load fetch evidence.")

<<<<<<< HEAD
<<<<<<< HEAD
=======
(defvar org-gcal-up-days 7
  "Past days requested from org-gcal; declared here for pre-load fetch evidence.")

>>>>>>> fb56d00 (Record org-gcal fetch evidence without claiming coverage)
(setq plstore-cache-passphrase-for-symmetric-encryption t)

=======
>>>>>>> c638f20 (update)
(setq org-gcal-remove-api-cancelled-events t
      org-gcal-remove-events-with-cancelled-todo t)

(defun my/org-gcal--auth-secret (host user)
  "Return the auth-source secret matching HOST and USER."
  (when-let* ((match (car (auth-source-search :host host
                                               :user user
                                               :max 1
                                               :require '(:secret))))
              (secret (plist-get match :secret)))
    (if (functionp secret) (funcall secret) secret)))

(defun my/org-gcal--file-credentials ()
  "Return the client ID and secret from `my/org-gcal-credentials-file'."
  (when (file-readable-p my/org-gcal-credentials-file)
    (with-temp-buffer
      (insert-file-contents my/org-gcal-credentials-file)
      (let ((document (json-parse-buffer :object-type 'plist)))
        (cons (plist-get document :client_id)
              (plist-get document :client_secret))))))

(defun my/org-gcal-configure ()
  "Load org-gcal credentials and calendar IDs from auth-source.

OAuth credentials come from `my/org-gcal-credentials-file', with auth-source
entries at host `org-gcal' as an optional override.  Calendar IDs use host
`org-gcal-calendar' with any of the users `main', `school', `work', and
`personal'.  The main calendar has no role mapping.
Calendar IDs are stored as secrets so personal addresses never enter the
dotfiles repository."
  (interactive)
  (let* ((file-credentials (my/org-gcal--file-credentials))
         (client-id (or (my/org-gcal--auth-secret "org-gcal" "client-id")
                        (car file-credentials)))
         (client-secret (or (my/org-gcal--auth-secret "org-gcal" "client-secret")
                            (cdr file-credentials)))
         (calendars
          (delq nil
                (mapcar
                 (lambda (entry)
                   (when-let* ((calendar-id
                                (my/org-gcal--auth-secret
                                 "org-gcal-calendar" (car entry))))
                     (cons calendar-id (cdr entry))))
                  '(("main" . nil)
                    ("school" . "school")
                    ("work" . "work")
                    ("personal" . "personal"))))))
    (unless client-id
      (user-error "Missing auth-source entry: org-gcal/client-id"))
    (unless client-secret
      (user-error "Missing auth-source entry: org-gcal/client-secret"))
    (unless calendars
      (user-error "Add at least one org-gcal-calendar entry to auth-source"))
    (setq org-gcal-client-id client-id
          org-gcal-client-secret client-secret
          my/org-gcal-calendar-role-alist calendars
<<<<<<< HEAD
          my/org-gcal-configured-p nil
=======
>>>>>>> c638f20 (update)
          org-gcal-fetch-file-alist
          (mapcar (lambda (entry)
                    (cons (car entry) my/org-gcal-calendar-file))
                  calendars))
    (when (called-interactively-p 'interactive)
      (message "org-gcal configured for %d calendar(s)"
               (length calendars)))
    calendars))

(defun my/org-gcal-role-for-calendar (calendar-id)
  "Return the canonical role mapped to CALENDAR-ID, or nil."
  (cdr (assoc calendar-id my/org-gcal-calendar-role-alist)))

(defun my/org-gcal-annotate-entry (calendar-id event _update-mode)
  "Add planning properties for CALENDAR-ID and Google EVENT at point."
  (unless (equal (plist-get event :status) "cancelled")
    (let* ((start (plist-get event :start))
           (role (my/org-gcal-role-for-calendar calendar-id))
           (busy (not (equal (plist-get event :transparency) "transparent")))
           (all-day (and (plist-get start :date) t))
           (event-type (or (plist-get event :eventType) "default")))
      (org-entry-put nil "GCAL_BUSY" (if busy "yes" "no"))
      (org-entry-put nil "GCAL_ALL_DAY" (if all-day "yes" "no"))
      (org-entry-put nil "GCAL_EVENT_TYPE" event-type)
      (if role
          (org-entry-put nil "CALENDAR_ROLE" role)
        (org-entry-delete nil "CALENDAR_ROLE")))))

(defun my/org-gcal--entry-timed-p ()
  "Return non-nil when the current event has a timestamp with a time."
  (save-excursion
    (org-back-to-heading t)
    (let ((end (save-excursion (outline-next-heading) (point))))
      (re-search-forward
       "<[^>\n]*[[:space:]][0-9][0-9]:[0-9][0-9]" end t))))

(defun my/org-gcal-normalize-calendar-buffer ()
  "Fill missing planning properties in `calendar.org'; return change status."
  (interactive)
  (with-current-buffer (find-file-noselect my/org-gcal-calendar-file)
    (let ((before (buffer-chars-modified-tick)))
      (org-with-wide-buffer
       (org-map-entries
        (lambda ()
           (let* ((calendar-id (org-entry-get nil "calendar-id"))
                  (role (my/org-gcal-role-for-calendar calendar-id)))
            (my/org-gcal--put-if-changed
             "GCAL_BUSY"
             (if (equal (org-entry-get nil "TRANSPARENCY") "transparent")
                 "no" "yes"))
            (my/org-gcal--put-if-changed
             "GCAL_ALL_DAY" (if (my/org-gcal--entry-timed-p) "no" "yes"))
             (unless (org-entry-get nil "GCAL_EVENT_TYPE")
               (org-entry-put nil "GCAL_EVENT_TYPE" "default"))
             (if role
                 (my/org-gcal--put-if-changed "CALENDAR_ROLE" role)
               (when (org-entry-get nil "CALENDAR_ROLE")
                 (org-entry-delete nil "CALENDAR_ROLE")))))
        nil 'file))
      (/= before (buffer-chars-modified-tick)))))

(defun my/org-gcal--put-if-changed (property value)
  "Set PROPERTY to VALUE at point only when its value differs."
  (unless (equal (org-entry-get nil property) value)
    (org-entry-put nil property value)))

(defun my/org-gcal--calendar-fingerprint ()
  "Return a content fingerprint for the calendar buffer."
  (with-current-buffer (find-file-noselect my/org-gcal-calendar-file)
    (secure-hash 'sha256 (current-buffer))))

(defun my/org-gcal--prepare-package ()
  "Configure and load org-gcal with current OAuth credentials."
<<<<<<< HEAD
  (unless my/org-gcal-configured-p
    (my/org-gcal-configure)
    (require 'org-gcal)
    (when (fboundp 'org-gcal-reload-client-id-secret)
      (org-gcal-reload-client-id-secret))
    (setq my/org-gcal-configured-p t)))
=======
  (my/org-gcal-configure)
  (require 'org-gcal)
  (when (fboundp 'org-gcal-reload-client-id-secret)
    (org-gcal-reload-client-id-secret)))
>>>>>>> c638f20 (update)

(defun my/org-gcal--record-successful-fetch (&optional fetched-at)
  "Record FETCHED-AT and requested window, NOT verified availability coverage.

org-gcal may swallow individual entry errors, and incremental sync does not
certify complete recurrence instances.  This receipt is untrusted for free time."
  (let ((fetched-at (or fetched-at (current-time))))
    (let* ((receipt-file (concat my/org-gcal-calendar-file ".sync-receipt.json"))
      (temp-file (make-temp-file (concat receipt-file ".") nil ".tmp"))
      (sha256 (with-temp-buffer
                (insert-file-contents-literally my/org-gcal-calendar-file)
                (secure-hash 'sha256 (current-buffer)))))
      (unwind-protect
          (progn
            (with-current-buffer (find-file-noselect my/org-gcal-calendar-file)
              (unless (and (not (buffer-modified-p))
                           (equal sha256 (secure-hash 'sha256 (current-buffer))))
                (error "Saved calendar differs from fetched/normalized buffer")))
            (with-temp-file temp-file
              (insert (json-encode
                       `((version . 2)
                         (availability . "unverified")
                         (sha256 . ,sha256)
                         (fetchedAt . ,(format-time-string "%Y-%m-%dT%H:%M:%SZ" fetched-at t))
                         (requestedStart . ,(format-time-string "%Y-%m-%dT%H:%M:%SZ"
                                                               (time-subtract fetched-at (days-to-time org-gcal-up-days)) t))
                         (requestedEnd . ,(format-time-string "%Y-%m-%dT%H:%M:%SZ"
                                                             (time-add fetched-at (days-to-time org-gcal-down-days)) t))))))
            (set-file-modes temp-file #o600)
            (rename-file temp-file receipt-file t))
        (when (file-exists-p temp-file) (delete-file temp-file))))
    (setq my/org-gcal-last-successful-fetch-time fetched-at
          my/org-gcal-calendar-coverage-end nil)))

(defun my/org-gcal-fetch ()
  "Fetch Google Calendar events without pushing local changes."
  (interactive)
  (if my/org-gcal-fetch-in-progress
      :already-running
    (my/org-gcal--prepare-package)
    (if (and (boundp 'org-gcal--sync-lock) org-gcal--sync-lock)
        :already-running
      (progn
        (setq my/org-gcal-fetch-in-progress t)
        (condition-case error-data
            (let* ((fetch (org-gcal-fetch))
                   (success
                    (deferred:nextc
                     fetch
                      (lambda (result)
                        (my/org-gcal-normalize-calendar-buffer)
                        (with-current-buffer
                            (find-file-noselect my/org-gcal-calendar-file)
                          (save-buffer))
                        (my/org-gcal--record-successful-fetch)
<<<<<<< HEAD
                        (setq my/org-gcal-last-poll-error nil)
=======
>>>>>>> c638f20 (update)
                        (when (fboundp 'my/lifeos-invalidate-project-analysis)
                          (my/lifeos-invalidate-project-analysis))
                        result)))
                   (watched
                    (deferred:watch
                     success
                     (lambda (_)
                       (setq my/org-gcal-fetch-in-progress nil)))))
              watched)
          (error
           (setq my/org-gcal-fetch-in-progress nil)
           (signal (car error-data) (cdr error-data))))))))

(defun my/org-gcal-full-refresh ()
  "Clear incremental sync state, then fetch all Google Calendar events."
  (interactive)
  (when my/org-gcal-fetch-in-progress
    (user-error "Google Calendar fetch already in progress"))
  (my/org-gcal--prepare-package)
  (org-gcal-sync-tokens-clear)
  (my/org-gcal-fetch))

<<<<<<< HEAD
(define-error 'my/org-gcal-authentication-required
  "Google Calendar authentication requires an explicit fetch" 'user-error)

(defun my/org-gcal--reject-background-auth (&rest _)
  "Prevent an automatic calendar fetch from opening a browser."
  (signal 'my/org-gcal-authentication-required nil))

(defun my/org-gcal--poll ()
  "Fetch calendars only after explicit authentication in this Emacs session."
  (if (not my/org-gcal-last-successful-fetch-time)
      :authentication-required
    (let ((browse-url-browser-function #'my/org-gcal--reject-background-auth))
      (condition-case error-data
          (my/org-gcal-fetch)
        (my/org-gcal-authentication-required
         (setq my/org-gcal-last-poll-error 'authentication-required)
         :authentication-required)
        (error
         (setq my/org-gcal-last-poll-error (error-message-string error-data))
         :failed)))))

(defun my/org-gcal-start-polling ()
  "Poll every fifteen minutes after one explicit successful fetch."
=======
(defun my/org-gcal-start-polling ()
  "Start one fetch shortly after startup and every fifteen minutes."
>>>>>>> c638f20 (update)
  (interactive)
  (when (timerp my/org-gcal-fetch-timer)
    (cancel-timer my/org-gcal-fetch-timer))
  (setq my/org-gcal-fetch-timer
<<<<<<< HEAD
        (run-at-time (* 15 60) (* 15 60) #'my/org-gcal--poll)))
=======
        (run-at-time 5 (* 15 60) #'my/org-gcal-fetch)))
>>>>>>> c638f20 (update)

(use-package org-gcal
  :straight t
  :commands (org-gcal-fetch org-gcal-sync)
  :init
  (setq org-gcal-up-days 7
        org-gcal-down-days 60
         org-gcal-auto-archive nil
         org-gcal-notify-p nil
         org-gcal-remove-api-cancelled-events t
         org-gcal-remove-events-with-cancelled-todo t
        org-gcal-strip-html-descriptions t
        org-gcal-managed-newly-fetched-mode "gcal"
        org-gcal-managed-update-existing-mode "gcal"))

(with-eval-after-load 'org-gcal
  (add-hook 'org-gcal-after-update-entry-functions
             #'my/org-gcal-annotate-entry))

(add-hook 'emacs-startup-hook #'my/org-gcal-start-polling)

(when (and after-init-time (not noninteractive))
  (my/org-gcal-start-polling))

(provide 'my-org-gcal)
