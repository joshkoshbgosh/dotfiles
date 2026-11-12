;; -*- lexical-binding: t -*-
;;; completion/vertico-posframe.el --- vertico in a child frame

;; `:after vertico' on its own does not load the package: use-package only
;; defers the `:config' block, so the mode is never turned on.  `:demand t' is
;; what makes it actually load once vertico is available.
;;
;; Child frames are fine on this setup: the Emacs binary is the X11/GTK3 build
;; running under XWayland, where a child frame is a real X child window of the
;; Emacs frame and the compositor never has to manage it.  The breakage people
;; report is with PGTK (native Wayland) builds, which emulate child frames with
;; separate surfaces.
;;
;; `my/toggle-vertico-posframe' stays as a quick escape hatch.

(use-package vertico-posframe
  :after vertico
  :demand t
  :init
  (setq vertico-posframe-parameters
        '((left-fringe . 8)
          (right-fringe . 8))
        vertico-posframe-poshandler #'posframe-poshandler-frame-center
        vertico-posframe-width 100)
  :config
  (vertico-posframe-mode 1))

(defun my/toggle-vertico-posframe ()
  "Toggle vertico-posframe on/off."
  (interactive)
  (if vertico-posframe-mode
      (vertico-posframe-mode -1)
    (vertico-posframe-mode 1)))
