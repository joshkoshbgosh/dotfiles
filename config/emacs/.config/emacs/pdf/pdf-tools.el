;; -*- lexical-binding: t -*-
;;; pdf/pdf-tools.el — PDF viewing

;; These four were bound in evil's normal state.  They are kept as plain
;; mode-map bindings so the vim-ish scrolling does not disappear with evil:
;; `j'/`k' scroll by line, `C-f'/`C-b' by page.  Native `n'/`p' are
;; page-turning commands and are untouched.
;;
;; Applied from `pdf-view', not from `pdf-tools' :config: `pdf-loader-install'
;; prompts on stdin when the epdfinfo helper is missing, and an error there
;; would abort the rest of the :config block.
(with-eval-after-load 'pdf-view
  (keymap-set pdf-view-mode-map "j" #'pdf-view-next-line-or-next-page)
  (keymap-set pdf-view-mode-map "k" #'pdf-view-previous-line-or-previous-page)
  (keymap-set pdf-view-mode-map "C-f" #'pdf-view-scroll-up-or-next-page)
  (keymap-set pdf-view-mode-map "C-b" #'pdf-view-scroll-down-or-previous-page))

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
                (pdf-view-roll-minor-mode -1)))))
