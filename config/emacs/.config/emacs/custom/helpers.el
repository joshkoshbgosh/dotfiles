;; -*- lexical-binding: t -*-
;;; custom/helpers.el — Cross-cutting custom helpers

(defun my/find-file-prompt ()
  "Find file, asking whether to open in a new window or current tab."
  (interactive)
  (let* ((file (read-file-name "Find file: "))
         (choice (read-char-choice "[w]indow / [t]ab: " '(?w ?t))))
    (pcase choice
      (?w (find-file-other-window file))
      (?t (find-file file)))))

