;; -*- lexical-binding: t -*-
;;; core/transient.el --- transient package (straight-managed, not built-in)

;; Dirvish 2.3.x expects newer transient internals than Emacs 30.2 ships.
;; Use the straight-managed package instead of the built-in copy.
(use-package transient
  :demand t)


