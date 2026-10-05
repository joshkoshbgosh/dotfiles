;; -*- lexical-binding: t -*-
;;; themes/doom-modeline.el — Doom modeline

(use-package doom-modeline
  :demand t
  :init
  (setq doom-modeline-height 40
        doom-modeline-modal-icon nil)   ; plain text state indicator (N/I/V) instead of circle icon
  :config
  ;; Hide noisy segments
  (setq doom-modeline-buffer-encoding nil       ; always utf-8, not useful
        doom-modeline-enable-buffer-position nil ; hide L478
        doom-modeline-percent-position nil)      ; hide 45%
  ;; Scale up the mode-line text (1.1 = 110% of default font size)
  (custom-set-faces
   '(mode-line          ((t :height 1.1)))
   '(mode-line-inactive ((t :height 1.1))))
  (doom-modeline-mode 1))

