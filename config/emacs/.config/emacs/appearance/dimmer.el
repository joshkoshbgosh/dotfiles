;; -*- lexical-binding: t -*-
;;; appearance/dimmer.el --- dim inactive windows

(use-package dimmer
  :demand t
  :config
  (dimmer-mode 1)
  (setq dimmer-fraction 0.15))

