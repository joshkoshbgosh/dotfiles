;; -*- lexical-binding: t -*-
;;; org/openspec.el — OpenSpec project context

(use-package openspec
  :straight (:host github :repo "Zacalot/openspec.el")
  :after org
  :config
  (defun my/openspec-project-file ()
    "Return the openspec project file path for the current project, or nil."
    (when-let* ((proj (project-current))
                (root (project-root proj))
                (spec-file (expand-file-name "openspec/project.md" root)))
      (when (file-exists-p spec-file)
        spec-file)))

  (defun my/openspec-capture-project ()
    "Capture a TODO into the current project's openspec-project.org file, or fall back to lifeos.org."
    (interactive)
    (if-let* ((proj (project-current))
              (root (project-root proj))
              (spec-dir (expand-file-name "openspec/" root)))
      (progn
        (unless (file-exists-p spec-dir)
          (make-directory spec-dir t))
        (let ((org-file (expand-file-name "project-todos.org" spec-dir)))
          (find-file org-file)
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (org-capture nil "t")))
    (org-capture nil "t")))

  (defun my/openspec-goto-project-todos ()
    "Open project-todos.org for the current project, or prompt for one."
    (interactive)
    (if-let* ((proj (project-current))
              (root (project-root proj))
              (spec-dir (expand-file-name "openspec/" root))
              (todo-file (expand-file-name "project-todos.org" spec-dir)))
      (find-file todo-file)
    (find-file (expand-file-name "lifeos.org" org-directory))))

  (with-eval-after-load 'general
    (my/leader
      "n p t" '(my/openspec-capture-project :which-key "capture project task")
      "n p f" '(my/openspec-goto-project-todos :which-key "find project todos"))))

