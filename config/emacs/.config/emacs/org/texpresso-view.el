;; -*- lexical-binding: t -*-
;;; org/texpresso-view.el --- live LaTeX preview (#8)

;; texpresso-view needs a *patched* TeXpresso build, not stock TeXpresso:
;;
;;   git clone -b texpresso-view https://github.com/stefanoconiglio/texpresso
;;   make -C texpresso all
;;
;; Set `my/texpresso-root' to that checkout. Until it exists this file is
;; inert, because `texpresso-view' requires TeXpresso's own `texpresso.el'
;; and the patched `build/texpresso' binary.
;;
;; Usage: open a .tex file, `M-x texpresso-view'.

(defvar my/texpresso-root (expand-file-name "~/src/texpresso")
  "Checkout of TeXpresso built with the texpresso-view patches.")

(when (and (file-directory-p my/texpresso-root)
           (file-exists-p (expand-file-name "build/texpresso" my/texpresso-root))
           (file-exists-p (expand-file-name "emacs/texpresso.el" my/texpresso-root)))
  (add-to-list 'load-path (expand-file-name "emacs" my/texpresso-root))

  (use-package texpresso
    :straight nil
    :custom
    (texpresso-binary (expand-file-name "build/texpresso" my/texpresso-root))
    (texpresso-follow-cursor t))

  (use-package texpresso-view
    :straight (:host github :repo "stefanoconiglio/emacs-texpresso-view")
    :after texpresso
    :commands (texpresso-view)))
