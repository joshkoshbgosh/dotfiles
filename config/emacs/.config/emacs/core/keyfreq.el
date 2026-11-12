;; -*- lexical-binding: t -*-
;;; core/keyfreq.el --- record command frequency (#13)

;; Every command you run is counted, so the ones worth a shortcut become
;; obvious. `M-x keyfreq-show' lists them by frequency (optionally for the
;; current major mode, with a prefix argument); `keyfreq-where-is' answers
;; "what is this command bound to right now?".

(use-package keyfreq
  :demand t
  :init
  ;; Keep the data out of the dotfiles repo.
  (setq keyfreq-file (expand-file-name "keyfreq.eld" my/state-dir)
        keyfreq-file-lock (expand-file-name "keyfreq.eld.lock" my/state-dir))
  :config
  (keyfreq-mode 1)
  (keyfreq-autosave-mode 1))
