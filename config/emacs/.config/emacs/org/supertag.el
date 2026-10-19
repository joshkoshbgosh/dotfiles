;; -*- lexical-binding: t -*-
;;; org/supertag.el — Supertag configuration for LifeOS

(use-package supertag
  :straight (:host github :repo "yibie/supertag")
  :after org
  :demand t
  :commands (supertag-add-link
             supertag-doctor
             supertag-menu
             supertag-sync-full-rescan)
  :init
  ;; These settings must be established before Supertag is loaded.
  (setq supertag-data-directory (expand-file-name ".supertag/" org-directory)
        supertag-sync-directories (list (file-name-as-directory org-directory))
        supertag-text-link-relation-types '("depends-on"))
  (unless (file-directory-p supertag-data-directory)
    (make-directory supertag-data-directory t))

  (defun my/lifeos-supertag-rescan ()
    "Reindex LifeOS files into the Supertag database."
    (interactive)
    (supertag-sync-full-rescan))

  :config
  (if supertag--initialized
      (my/lifeos-initialize-canonical-supertags)
    (add-hook 'emacs-startup-hook
              #'my/lifeos-initialize-canonical-supertags 90)))
