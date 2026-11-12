;; -*- lexical-binding: t -*-
;;; modes/excali-mode.el --- Excalidraw inside Emacs (#17)

;; excali-mode draws .excalidraw files with the canvas API that landed in
;; Emacs 32 (master as 32.0.50; no 32.x release yet). On 31.1 it cannot load,
;; so it is only wired up when a 32+ Emacs is running.
;;
;; To try it: install `emacs-git' from the AUR and launch that binary.

(when (version<= "32" emacs-version)
  (use-package excali-mode
    :straight (:host github :repo "yibie/excali-mode")
    :mode "\\.excalidraw\\'"))
