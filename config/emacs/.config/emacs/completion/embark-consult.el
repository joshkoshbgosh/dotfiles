;; -*- lexical-binding: t -*-
;;; completion/embark-consult.el — embark + consult integration

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

