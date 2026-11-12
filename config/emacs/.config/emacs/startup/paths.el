;; -*- lexical-binding: t -*-
;;; startup/paths.el --- machine-specific path variables

(defvar my/workspace-dirs '("~/Workspace/" "~/Work/")
  "Candidate workspace roots across machines.")

(defun my/first-existing-dir (dirs)
  "Return the first existing directory from DIRS, or nil."
  (seq-find #'file-directory-p dirs))

(defvar my/current-workspace-dir
  (or (my/first-existing-dir my/workspace-dirs)
      "~/Workspace/")
  "Workspace root for the current machine.")

(defvar my/lifeos-dir
  (or (my/first-existing-dir
       (mapcar (lambda (dir)
                 (expand-file-name "lifeos/" dir))
               my/workspace-dirs))
      (expand-file-name "lifeos/" my/current-workspace-dir))
  "LifeOS root for the current machine.")

(defvar my/config-root-dir
  (file-name-directory
   (file-truename (or user-init-file load-file-name buffer-file-name)))
  "Directory containing this Emacs config.")

(defvar my/state-dir
  (expand-file-name "emacs/" (or (getenv "XDG_STATE_HOME") "~/.local/state"))
  "Directory for persistent state that is not tracked in the dotfiles repo.")

(make-directory my/state-dir t)


