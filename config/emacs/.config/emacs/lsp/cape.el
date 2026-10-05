;; -*- lexical-binding: t -*-
;;; lsp/cape.el — Cape completion-at-point sources

(use-package cape
  :after corfu
  :init
  ;; Add useful completion-at-point sources
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev))

