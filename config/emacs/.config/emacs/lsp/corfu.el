;; -*- lexical-binding: t -*-
;;; lsp/corfu.el — Corfu completion UI

(use-package corfu
  :demand t
  :init
  (setq corfu-auto t
        corfu-cycle t
        corfu-preview-current nil)
  :config
  (global-corfu-mode 1))

