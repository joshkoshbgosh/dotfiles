;; -*- lexical-binding: t -*-
;;; window/popper.el --- popup manager

;; Popups (help, compilation, grep, backtraces, agent output) are kept out of
;; the window layout and raised/buried on demand, instead of either stealing a
;; split or being buried somewhere you never find again.
;;
;;   C-`    toggle the latest popup
;;   M-`    cycle through the popup stack
;;   C-M-`  toggle whether the buffer at point is a popup
;;
;; `popper-echo-mode' (a hint list in the echo area) is deliberately left off.

(use-package popper
  :straight (:host github :repo "karthink/popper" :files ("*.el"))
  ;; Loaded eagerly: popper has to see a popup when it is *displayed*, so it
  ;; cannot wait for the first `C-`' press to be installed.
  :demand t
  :bind (("C-`"   . popper-toggle)
         ("M-`"   . popper-cycle)
         ("C-M-`" . popper-toggle-type))
  :init
  (setq popper-reference-buffers
        '(;; major modes: any buffer in these is a popup
          help-mode
          helpful-mode
          compilation-mode
          ;; name patterns; `hide' means "never auto-display", only pop on demand
          ("\\*Messages\\*"            . hide)
          ("\\*Warnings\\*"            . hide)
          ("\\*Backtrace\\*"           . hide)
          ("\\*Compile-Log\\*"         . hide)
          ("\\*Async Shell Command\\*" . hide)
          ("Shell Command Output\\*"   . hide)
          ("\\*Process List\\*"        . hide)
          ("\\*Embark.*\\*"            . hide)
          ("\\*grep\\*"                . hide)
          ("\\*rg\\*"                  . hide)
          ("\\*xref\\*"                . hide)
          ("\\*EGLOT.*\\*"             . hide)
          ("\\*Flymake.*\\*"           . hide))
        ;; No "POP" tag in the mode line; the dirvish hint was removed for the
        ;; same reason.  Set to " POP" if you want the marker back.
        popper-mode-line nil)
  :config
  (popper-mode +1))
