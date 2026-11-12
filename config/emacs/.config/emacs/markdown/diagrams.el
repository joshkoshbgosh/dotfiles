;; -*- lexical-binding: t -*-
;;; markdown/diagrams.el --- d2 / mermaid / plantuml / graphviz blocks (#2)

;; The diagram modes are installed as real major modes and mapped to fence
;; languages, instead of being switched on in every markdown/org buffer (which
;; stacks four minor modes onto unrelated files).
;;
;;   markdown: `C-c '' (`markdown-edit-code-block') opens the block in the
;;             language's mode in an indirect buffer.
;;   org:      `C-c '' (`org-edit-src-code') does the same for #+begin_src.
;;
;; `markdown-edit-code-block' needs edit-indirect.

(use-package edit-indirect
  :straight t)

(use-package d2-mode
  :straight t
  :mode "\\.d2\\'")

(use-package mermaid-mode
  :straight t
  :mode "\\.mmd\\'")

(use-package plantuml-mode
  :straight t
  :mode ("\\.puml\\'" "\\.plantuml\\'"))

(use-package graphviz-dot-mode
  :straight t
  :mode "\\.dot\\'")

(with-eval-after-load 'markdown-mode
  (dolist (pair '(("d2" . d2-mode)
                  ("mermaid" . mermaid-mode)
                  ("plantuml" . plantuml-mode)
                  ("puml" . plantuml-mode)
                  ("dot" . graphviz-dot-mode)))
    (add-to-list 'markdown-code-lang-modes pair)))

(with-eval-after-load 'org
  ;; Values are mode names without the "-mode" suffix ("dot" is already
  ;; mapped to graphviz-dot by default).
  (dolist (pair '(("d2" . d2)
                  ("mermaid" . mermaid)
                  ("plantuml" . plantuml)))
    (add-to-list 'org-src-lang-modes pair)))
