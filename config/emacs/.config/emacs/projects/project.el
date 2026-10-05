;; -*- lexical-binding: t -*-
;;; projects/project.el — project.el configuration

(use-package project
  :straight (:type built-in)
  :demand t
  :init
  (setq project-list-file (expand-file-name "projects.eld" user-emacs-directory)
        project-search-path (list (expand-file-name my/current-workspace-dir)))
  :config
  (my/leader
    "p"   '(:ignore t :which-key "project")
    "p p" '(project-switch-project :which-key "switch project")
    "p f" '(project-find-file :which-key "find file")
    "p b" '(project-switch-to-buffer :which-key "switch buffer")
    "p d" '(project-find-dir :which-key "find dir")
    "p !" '(project-shell-command :which-key "shell command")
    "p c" '(project-compile :which-key "compile")))

