;; -*- lexical-binding: t -*-
;;; leader/general.el --- M-; leader keys via general

(use-package general
  :after evil
  :config
  (general-create-definer my/leader
    :states '(normal visual motion emacs)
    :keymaps 'override
    :prefix "M-;"
    :global-prefix "C-M-;")

  (my/leader
    ";" '(execute-extended-command :which-key "M-x")
    "f"   '(:ignore t :which-key "files")
    "f f" '(my/find-file-prompt :which-key "find file")
    "f r" '(recentf-open-files :which-key "recent files")
    "b"   '(:ignore t :which-key "buffers")
    "b b" '(consult-buffer :which-key "switch buffer")
    "b d" '(kill-current-buffer :which-key "kill buffer")
    "b D" '(centaur-tabs-kill-other-buffers-in-current-group :which-key "kill other buffers in group")
    "b n" '(centaur-tabs-forward :which-key "next tab")
    "b p" '(centaur-tabs-backward :which-key "prev tab")
    "w"   '(:ignore t :which-key "windows")
    "w /" '(split-window-right :which-key "split right")
    "w -" '(split-window-below :which-key "split below")
    "w d" '(delete-window :which-key "delete window")
    ;; Registered eagerly — packages load lazily but bindings must exist at startup
    "s"   '(:ignore t :which-key "search")
    "s r" '(consult-ripgrep :which-key "ripgrep")
    "s l" '(consult-line :which-key "line")
    "s f" '(consult-find :which-key "find file")
    "s o" '(consult-outline :which-key "outline")
    "s i" '(consult-imenu :which-key "imenu")
    "s d" '(consult-dir :which-key "directory")
    "/"   '(consult-ripgrep :which-key "search project")
    "t"   '(:ignore t :which-key "toggles")
    "t t" '(consult-theme :which-key "choose theme")
    "c"   '(:ignore t :which-key "code")
    "c a" '(eglot-code-actions :which-key "code actions")
    "c r" '(eglot-rename :which-key "rename")
    "c f" '(eglot-format :which-key "format")
    "c d" '(xref-find-definitions :which-key "definition")
    "c R" '(xref-find-references :which-key "references")
    "c k" '(eldoc-doc-buffer :which-key "hover / type info")
    "c n" '(flymake-goto-next-error :which-key "next error")
    "c p" '(flymake-goto-prev-error :which-key "prev error")
    "c e" '(consult-flymake :which-key "error list")
    "c D" '(flymake-show-buffer-diagnostics :which-key "diagnostics buffer")
    "c i" '(eglot-find-implementation :which-key "implementation")
    "n"   '(:ignore t :which-key "notes")
    "n c" '(org-capture :which-key "capture")
    "n a" '(org-agenda :which-key "agenda")
    "n d" '((lambda () (interactive) (org-agenda nil "d")) :which-key "dashboard")
    "n t" '(my/org-open-today :which-key "today")
    "n h" '((lambda () (interactive) (org-agenda nil "h")) :which-key "habits")
    "n r" '((lambda () (interactive) (org-agenda nil "r")) :which-key "reviews")
    "n f" '(org-roam-node-find :which-key "find node")
    "n i" '(org-roam-node-insert :which-key "insert link")
    "n g" '(org-roam-graph :which-key "graph")
    "n p"   '(:ignore t :which-key "project")
    "n s" '(org-sidebar :which-key "sidebar")
    "n S" '(org-sidebar-tree :which-key "sidebar tree")
    "n P" '(org-pomodoro :which-key "pomodoro")
    "o"   '(:ignore t :which-key "open")
    "o t" '(vterm :which-key "vterm"))

  ;; M-hjkl window navigation (works in all evil states and emacs state)
  (general-define-key
    :keymaps 'override
    "M-h" #'windmove-left
    "M-j" #'windmove-down
    "M-k" #'windmove-up
    "M-l" #'windmove-right)

  ;; H/L for tab switching in normal mode (LazyVim-style)
  (general-define-key
    :states '(normal)
    :keymaps 'override
    "H" #'centaur-tabs-backward
    "L" #'centaur-tabs-forward))
