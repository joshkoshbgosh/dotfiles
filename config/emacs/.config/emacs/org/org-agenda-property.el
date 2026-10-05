;; -*- lexical-binding: t -*-
;;; org/org-agenda-property.el — Agenda property columns

(use-package org-agenda-property
  :after org
  :config
  (setq org-agenda-property-list '("ENERGY" "CONTEXT" "RELATED_PROJECT" "REVIEW_FREQUENCY"))
  (setq org-agenda-property-position 'right))

