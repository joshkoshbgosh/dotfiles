;; -*- lexical-binding: t -*-
;;; org/org.el — Core org settings + agenda custom commands

(use-package org
  :straight (:type built-in)
  :init
  (setq org-directory (expand-file-name my/lifeos-dir)
        org-hide-emphasis-markers t
        org-startup-indented t
        org-ellipsis " ▾"
        org-log-done 'time
        org-src-tab-acts-natively t
        org-confirm-babel-evaluate nil
        org-id-link-to-org-use-id t
        org-id-locations-file (expand-file-name ".org-id-locations" user-emacs-directory))
  (with-eval-after-load 'org
  (add-to-list 'org-modules 'org-habit t)
  (org-load-modules-maybe t)

  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (python . t)
     (shell . t)))

  (add-hook 'org-capture-prepare-final-hook 'org-id-get-create)

  (let* ((lifeos (expand-file-name "lifeos.org" org-directory))
          (journal (expand-file-name "journal.org" org-directory))
          (goal-year (format-time-string "%Y")))
     (setq org-default-notes-file lifeos
           org-agenda-files (list lifeos)
           org-refile-targets `((,lifeos :maxlevel . 3))
           org-outline-path-complete-in-steps nil
           org-refile-use-outline-path 'file
           org-enforce-todo-dependencies t
           org-cycle-hide-drawer-startup t
           org-hide-leading-stars t
           org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "SOMEDAY(s)" "|" "DONE(d)" "CANCELLED(c)"))
           org-agenda-custom-commands
           (list
            `("d" "LifeOS dashboard"
               ((org-agenda-span 1)
                (org-deadline-warning-days 7)
                (org-agenda-overriding-header "Today")))
            (alltodo ""
                     ((org-agenda-overriding-header "Inbox And Tasks")
                      (org-agenda-files (list ,lifeos))
                      (org-super-agenda-groups
                       '((:name "Overdue" :deadline past)
                         (:name "Due Today" :deadline today)
                         (:name "Scheduled Today" :scheduled today)
                         (:name "Next Actions" :todo "NEXT")
                         (:name "Waiting" :todo "WAITING")
                         (:name "Someday" :todo "SOMEDAY")
                         (:discard (:todo "DONE"))
                         (:discard (:todo "CANCELLED"))))))
            (alltodo ""
                     ((org-agenda-overriding-header "Projects")
                      (org-agenda-files (list ,lifeos))
                      (org-super-agenda-groups
                       '((:name "Active Projects" :todo "NEXT")
                         (:name "Waiting Projects" :todo "WAITING")
                         (:name "Project Backlog" :todo "TODO")
                         (:name "Someday Projects" :todo "SOMEDAY")
                         (:discard (:todo "DONE"))
                         (:discard (:todo "CANCELLED"))))))
              `("n" "Next actions" todo "NEXT"
                ((org-agenda-files (list ,lifeos))))
              `("w" "Waiting" todo "WAITING"
                ((org-agenda-files (list ,lifeos))))
             `("r" "Project reviews" alltodo ""
                ((org-agenda-overriding-header "Project Reviews")
                 (org-agenda-files (list ,lifeos))
                 (org-super-agenda-groups
                  '((:name "Active Projects" :todo "NEXT")
                     (:name "Waiting Projects" :todo "WAITING")
                     (:name "Backlog Projects" :todo "TODO")
                     (:discard (:todo "DONE"))
                     (:discard (:todo "CANCELLED"))))))
              `("h" "Habits" alltodo ""
                ((org-agenda-files (list ,lifeos))
                (org-agenda-overriding-header "Habits")
                (org-super-agenda-groups
                 '((:name "Habits" :todo ("TODO" "NEXT" "WAITING" "SOMEDAY"))
                    (:discard (:todo "DONE"))
                    (:discard (:todo "CANCELLED"))))))))
   ))
  )

;; --- Org helpers ---

(defun my/org-today-file ()
  "Return path to today's daily note file."
  (expand-file-name (format-time-string "daily/%Y-%m-%d.org") org-directory))

(defun my/org-open-today ()
  "Open today's daily note."
  (interactive)
  (find-file (my/org-today-file)))

(defun my/lifeos-file (name)
  "Return absolute path for NAME inside `org-directory'."
  (expand-file-name name org-directory))

(defun my/lifeos-open-file (name)
  "Open lifeos file NAME from `org-directory'."
  (interactive)
  (find-file (my/lifeos-file name)))


;; Move completed items to "* Completed" heading in same file
(defun my/org-archive-completed-to-completed-section ()
  "Archive completed/cancelled TODO items to a '* Completed' heading in the same file."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((completed-heading nil))
      ;; Find or create "* Completed" heading
      (while (and (not completed-heading)
                  (re-search-forward "^\\*+ " nil t))
        (when (string-equal (org-get-heading t t t t) "Completed")
          (setq completed-heading (point))))
      (unless completed-heading
        (goto-char (point-max))
        (insert "\n* Completed\n")
        (setq completed-heading (point)))
      ;; Now move completed items
      (goto-char (point-min))
      (while (re-search-forward org-heading-regexp nil t)
        (let* ((todo-state (org-get-todo-state))
               (is-done (member todo-state '("DONE" "CANCELLED"))))
          (when is-done
            (let ((heading-start (point-at-bol))
                  (heading-end (save-excursion
                                 (outline-next-heading)
                                 (point))))
              (kill-region heading-start heading-end)
              (goto-char completed-heading)
              (yank)
              (setq completed-heading (point))
              (goto-char heading-start))))))))

