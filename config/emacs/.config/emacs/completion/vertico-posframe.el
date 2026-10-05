;; -*- lexical-binding: t -*-
;;; completion/vertico-posframe.el --- vertico posframe integration

(use-package vertico-posframe
  :after vertico
  :config
  (setq vertico-posframe-parameters
        '((left-fringe . 8)
          (right-fringe . 8))
        vertico-posframe-poshandler #'posframe-poshandler-frame-center
        vertico-posframe-width 100)
  (vertico-posframe-mode 1))

(defun my/toggle-vertico-posframe ()
  "Toggle vertico-posframe on/off (escape hatch for Wayland issues)."
  (interactive)
  (if vertico-posframe-mode
      (vertico-posframe-mode -1)
    (vertico-posframe-mode 1)))

