;; -*- lexical-binding: t -*-
;;; browser/embr.el --- Chromium rendered inside Emacs (#18)

;; Headless Chromium draws the page; Emacs shows it. Native canvas rendering
;; (faster, no per-frame JPEG) needs Emacs 32; on 31.1 it falls back cleanly.
;;
;; One-time setup after the package is installed:
;;   M-x embr-install-or-update-chromium
;; which provisions Playwright and the vanilla (open-source) Chromium build.

(use-package embr
  :straight (:host github :repo "emacs-os/embr.el"
             :files ("*.el" "*.py" "*.sh" "native/*.c" "native/Makefile"))
  :commands (embr-browse embr-browse-incognito)
  :custom
  ;; Vanilla Playwright Chromium (the default is CloakBrowser, closed-source).
  (embr-browser-engine 'chromium)
  (embr-home-url "about:blank")
  (embr-color-scheme 'dark)
  (embr-viewport-sizing 'dynamic)
  (embr-scroll-method 'instant)
  (embr-render-backend 'auto))
