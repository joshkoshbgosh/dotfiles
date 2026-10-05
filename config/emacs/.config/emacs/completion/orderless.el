;; -*- lexical-binding: t -*-
;;; completion/orderless.el --- completion style

(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

