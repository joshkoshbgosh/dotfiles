;; -*- lexical-binding: t -*-
;;; lsp/eglot.el — Eglot LSP client configuration

;; Tree-sitter grammar sources
(setq treesit-language-source-alist
      '((typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
        (tsx        "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
        (javascript "https://github.com/tree-sitter/tree-sitter-javascript" "master" "src")))

;; (treesit-query-compile predicate-strip advice lives near top of init.el so
;; it's installed before persp-mode restores any .ts/.tsx buffers.)

(use-package eglot
  :commands (eglot eglot-ensure)
  :init
  ;; Auto-install missing tree-sitter grammars
  (defun my/treesit-install-missing-grammars ()
    "Install missing tree-sitter grammars for typescript, tsx, and javascript."
    (dolist (lang '(typescript tsx javascript))
      (unless (treesit-language-available-p lang)
        (treesit-install-language-grammar lang))))

  (add-hook 'emacs-startup-hook #'my/treesit-install-missing-grammars)

  ;; Auto-start LSP for TypeScript/JavaScript modes
  (dolist (mode '(typescript-ts-mode tsx-ts-mode js-ts-mode))
    (add-hook (intern (format "%s-hook" mode)) #'eglot-ensure))
  ;; Associate TS files with proper major modes
  (add-to-list 'auto-mode-alist '("\\.ts\\'"  . typescript-ts-mode))
  (add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))
  (add-to-list 'auto-mode-alist '("\\.js\\'"  . js-ts-mode))
  (add-to-list 'auto-mode-alist '("\\.jsx\\'" . js-ts-mode))

  (with-eval-after-load 'eglot
    (setq eglot-autoshutdown t
          eglot-send-changes-idle-time 0.2)
    ;; Use vtsls for TypeScript (install: npm install -g @vtsls/language-server)
    (add-to-list 'eglot-server-programs
                 '((typescript-ts-mode tsx-ts-mode) . ("vtsls" "--stdio")))
    ;; Route xref through consult for telescope-style references popup
    (with-eval-after-load 'consult
      (require 'consult-xref)
      (setq xref-show-xrefs-function      #'consult-xref
            xref-show-definitions-function #'consult-xref))
    ;; consult-flymake for error list
    (with-eval-after-load 'consult
      (require 'consult-flymake))))

