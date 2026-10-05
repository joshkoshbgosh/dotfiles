;; -*- lexical-binding: t -*-
;;; org/org-time-budgets.el — Time budgets for org agenda

(use-package org-time-budgets
  :after org
  :config
  (setq org-time-budgets
        `((:title "Work"    :match "work"     :budget "6:00"  :blocks (workday week))
          (:title "School"  :match "school"   :budget "4:00"  :blocks (workday week))
          (:title "Personal" :match "personal" :budget "3:00"  :blocks (day week)))))

