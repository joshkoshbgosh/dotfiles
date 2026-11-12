;; -*- lexical-binding: t -*-
;;; pdf/pdf-tools.el — PDF viewing

(use-package pdf-tools
  :mode (("\\.pdf\\'" . pdf-view-mode))
  :config
  (pdf-loader-install)
  (setq-default pdf-view-display-size 'fit-width)
  (add-hook 'pdf-view-mode-hook
            (lambda ()
              (display-line-numbers-mode -1)
              ;; pdf-tools is prone to flicker and page resets when global
              ;; auto-revert polls these buffers.
              (auto-revert-mode -1)
              ;; `pdf-view-roll-minor-mode' currently breaks navigation in this
              ;; setup; keep the standard page-aware pdf-view bindings.
              (when (bound-and-true-p pdf-view-roll-minor-mode)
                (pdf-view-roll-minor-mode -1))
              (when (bound-and-true-p evil-local-mode)
                (evil-normal-state))))
  (with-eval-after-load 'evil
    (evil-set-initial-state 'pdf-view-mode 'normal)
    (evil-define-key 'normal pdf-view-mode-map
      (kbd "j") #'pdf-view-next-line-or-next-page
      (kbd "k") #'pdf-view-previous-line-or-previous-page
      (kbd "C-f") #'pdf-view-scroll-up-or-next-page
      (kbd "C-b") #'pdf-view-scroll-down-or-previous-page)))

