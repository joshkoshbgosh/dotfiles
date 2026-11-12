;; -*- lexical-binding: t -*-
;;; core/undo-fu.el — undo that does not undo the undo

;; undo-fu used to be wired in through `evil-undo-system'.  With evil gone it
;; needs its own bindings, otherwise `C-/' would fall back to the built-in
;; `undo', which turns a redo into another undo as soon as you type after an
;; undo.  `C-?' is `undo-redo' in Emacs 31; point it at undo-fu too so the
;; pair behaves as one system.

(use-package undo-fu
  :demand t
  :bind (("C-/" . undo-fu-only-undo)
         ("C-_" . undo-fu-only-undo)
         ("C-x u" . undo-fu-only-undo)
         ("C-?" . undo-fu-only-redo)))
