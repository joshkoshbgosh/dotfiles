;; -*- lexical-binding: t -*-
;;; completion/embark.el — embark actions

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim))
  :init
  (setq embark-indicators
        '(embark-mixed-indicator
          embark-highlight-indicator
          embark-isearch-highlight-indicator))
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none))))

  :config
  ;; Add magit-status action for files/directories
  (define-key embark-file-map (kbd "g") #'magit-status))
