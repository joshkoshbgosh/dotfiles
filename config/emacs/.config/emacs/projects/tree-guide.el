;; -*- lexical-binding: t -*-
;;; projects/tree-guide.el --- indentation guide lines for lisp (#9)

;; Renders the sexp structure of elisp buffers as tree guide lines. Lisp only
;; (it uses `syntax-ppss'), so it is hooked to `emacs-lisp-mode' and not
;; enabled globally.

(use-package tree-guide
  :straight (:host github :repo "benvvalk/tree-guide.el")
  :hook (emacs-lisp-mode . tree-guide-mode))
