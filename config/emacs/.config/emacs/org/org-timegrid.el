;; -*- lexical-binding: t -*-
;;; org/org-timegrid.el --- week calendar over org files (#7)

;; A drag-to-create week view backed by org timestamps. New entries land in
;; calendar.org, which is already part of `org-agenda-files'.
;;
;; Bound to `C-c w', not `C-c c': Org already owns `C-c c' (org-capture) on the
;; global map, and capture matters more than the week grid.

(use-package org-timegrid
  ;; Pinned to the repo: the MELPA recipe checkout here predates this package.
  :straight (:host github :repo "Gleek/org-timegrid" :files ("*.el"))
  :commands (org-timegrid-week)
  :bind ("C-c w" . org-timegrid-week)
  :init
  (setq org-timegrid-org-capture-file
        (expand-file-name "calendar.org" org-directory))
  :config
  (require 'org-timegrid-org))

;; Optional read-only day strip inside the agenda buffer. This is a file
;; inside org-timegrid, not a separate package.
(use-package org-timegrid-agenda
  :straight nil
  :after (org-timegrid org-agenda)
  :config
  (org-timegrid-agenda-mode 1))
