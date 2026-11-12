;; -*- lexical-binding: t -*-
;;; projects/project.el — project.el configuration

(use-package project
  :straight (:type built-in)
  :demand t
  :init
  (setq project-list-file (expand-file-name "projects.eld" user-emacs-directory)
        project-search-path (list (expand-file-name my/current-workspace-dir))))

