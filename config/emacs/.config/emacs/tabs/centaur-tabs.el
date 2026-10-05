;; -*- lexical-binding: t -*-
;;; tabs/centaur-tabs.el --- LazyVim-style buffer tabs

(use-package centaur-tabs
  :demand t
  :init
  (setq centaur-tabs-style "bar"
        centaur-tabs-height 32
        centaur-tabs-set-icons t
        centaur-tabs-icon-type 'nerd-icons
        centaur-tabs-set-modified-marker t
        centaur-tabs-modified-marker "●"
        centaur-tabs-close-button "✕"
        centaur-tabs-set-bar 'under
        centaur-tabs-show-new-tab-button nil
        centaur-tabs-set-close-button t)
  :config
  (centaur-tabs-mode 1)
  ;; Group tabs by project.el
  (defun my/centaur-tabs-project-group ()
    "Group tabs by project.el root."
    (list (let ((proj (project-current)))
            (if proj
                (file-name-nondirectory (directory-file-name (project-root proj)))
              "Other"))))
  (setq centaur-tabs-buffer-groups-function #'my/centaur-tabs-project-group)
  ;; Only show file-visiting buffers; exclude special/terminal buffers
  (defun my/centaur-tabs-buffer-list ()
    "Return buffers to show as tabs — exclude special and terminal buffers."
    (seq-filter
     (lambda (b)
       (let ((name (buffer-name b)))
         (and (not (string-prefix-p "*" name))
              (not (string-prefix-p " " name))
              (not (with-current-buffer b
                     (derived-mode-p 'vterm-mode 'magit-mode 'dired-mode))))))
     (buffer-list)))
  (setq centaur-tabs-buffer-list-function #'my/centaur-tabs-buffer-list)
  ;; Cycle only within visible tabs (wrap around, don't jump to other windows)
  (setq centaur-tabs-cycle-scope 'tabs)
  ;; Color tab text based on git vc-state (matches diff-hl fringe colors)
  (setq centaur-tabs-buffer-face-function
        (lambda (buf)
          (with-current-buffer buf
            (when (and buffer-file-name
                       (vc-registered buffer-file-name))
              (pcase (vc-state buffer-file-name)
                ('edited  'diff-hl-change)
                ('added   'diff-hl-insert)
                ('removed 'diff-hl-delete)
                (_         nil)))))))

