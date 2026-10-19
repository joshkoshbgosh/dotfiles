;; -*- lexical-binding: t -*-
;;; completion/marginalia.el --- annotated completion candidates

(use-package marginalia
  :after vertico
  :demand t
  :config (marginalia-mode 1))
