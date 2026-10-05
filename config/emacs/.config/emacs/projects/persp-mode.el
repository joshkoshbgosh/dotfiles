;; -*- lexical-binding: t -*-
;;; projects/persp-mode.el — workspace/perspective management

(use-package persp-mode
  :demand t
  :init
  (setq persp-autosave-mode t
        persp-auto-resume-time 0
        persp-save-window-conf t
        persp-save-dir (expand-file-name "persp/" user-emacs-directory))
  :config
  (persp-mode 1)
  ;; Load saved perspectives if they exist
  (let ((state-file (expand-file-name "persp-auto-save" persp-save-dir)))
    (when (file-exists-p state-file)
      (condition-case nil
          (persp-load-state-from-file state-file)
        (error (message "Warning: Could not restore persp-mode state")))))
  (my/leader
    "TAB" '(:ignore t :which-key "workspace")
    "TAB TAB" '(persp-switch :which-key "switch")
    "TAB n"   '(persp-next :which-key "next")
    "TAB p"   '(persp-prev :which-key "prev")
    "TAB k"   '(persp-kill :which-key "kill")))

(defun my/workspace-switch-to-project ()
  "Pick a directory, treat it as a project, switch to a workspace for it."
  (interactive)
  (let* ((dir (read-directory-name "Project dir: " my/current-workspace-dir nil t))
         (dir (file-name-as-directory (expand-file-name dir)))
         (name (file-name-nondirectory (directory-file-name dir)))
         (proj (project-current nil dir)))
    ;; Only remember if project.el can detect a real project (e.g., git repo).
    (when proj
      (project-remember-project proj))
    (persp-switch name)
    (dired dir)))

(defun my/workspace-project-magit ()
  "Project -> workspace -> magit-status."
  (interactive)
  (let* ((dir (project-prompt-project-dir))
         (name (file-name-nondirectory (directory-file-name dir))))
    (persp-switch name)
    (magit-status dir)))

