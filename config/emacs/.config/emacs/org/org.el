;; -*- lexical-binding: t -*-
;;; org/org.el — Core org settings + agenda custom commands

(use-package org
  :straight (:type built-in)
  :init
  (setq org-directory (expand-file-name my/lifeos-dir)
        org-hide-emphasis-markers t
        org-startup-indented t
        org-log-done 'time
        org-src-tab-acts-natively t
        org-confirm-babel-evaluate nil
        org-id-link-to-org-use-id t
        org-id-locations-file (expand-file-name ".org-id-locations" user-emacs-directory))
  (with-eval-after-load 'org
  (add-to-list 'org-modules 'org-habit t)
  (org-load-modules-maybe t)

  (add-hook 'org-capture-prepare-final-hook 'org-id-get-create)

  (let* (
	 (inbox (expand-file-name "inbox.org" org-directory))
	 (projects (expand-file-name "projects.org" org-directory))
	 (habits (expand-file-name "habits.org" org-directory))
	 (routines (expand-file-name "routines.org" org-directory))
         (journal (expand-file-name "journal.org" org-directory))
         (done (expand-file-name "done.org" org-directory))
         (planning (expand-file-name "planning.org" org-directory))
         (calendar (expand-file-name "calendar.org" org-directory))
        )
     (setq org-default-notes-file inbox
           org-agenda-files (list inbox projects habits routines journal done planning calendar)
           org-refile-targets `((t inbox) (t projects) (t habits) (t routines) (t journal) (t done))
           org-outline-path-complete-in-steps nil
           org-refile-use-outline-path 'file
           org-enforce-todo-dependencies t
           org-cycle-hide-drawer-startup t
           org-hide-leading-stars t
           org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "SOMEDAY(s)" "|" "DONE(d)" "CANCELLED(c)"))
   )))
  )

;; --- Org helpers ---

(defun my/org-today-file ()
  "Return path to today's daily note file."
  (expand-file-name (format-time-string "daily/%Y-%m-%d.org") org-directory))

(defun my/org-open-today ()
  "Open today's daily note."
  (interactive)
  (find-file (my/org-today-file)))
