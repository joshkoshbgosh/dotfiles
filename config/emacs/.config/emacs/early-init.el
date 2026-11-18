;; -*- lexical-binding: t -*-

;; Faster startup / less UI junk early
(setq package-enable-at-startup nil)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(setq inhibit-startup-screen t)

;; Prevent macOS from restoring windows/sessions
(setq ns-use-native-fullscreen nil
      ns-use-srgb-colorspace t)

;; Maximize frame on startup (full viewport, not full-screen)
(add-to-list 'default-frame-alist '(fullscreen . maximized))

;; Reduce GC during startup (we'll restore later)
(setq gc-cons-threshold (* 128 1024 1024)
      gc-cons-percentage 0.6)

;; Bound cold-cache compilation cost before loading any packages.  Use one
;; worker on the Mac to leave resources for the UI; keep four on Linux.
;; Existing native-compiled packages remain usable.
(setq native-comp-async-jobs-number (if (eq system-type 'darwin) 1 4))

;; Keep compiler diagnostics in *Warnings* without repeatedly displaying it
;; on macOS.  This does not suppress the log or disable native compilation.
(when (eq system-type 'darwin)
  (setq native-comp-async-report-warnings-errors 'silent))

;; Silence noisy upstream native-comp warnings from packages we don't patch.
(when (boundp 'native-comp-jit-compilation-deny-list)
  (dolist (re '("general\\.el\\'"
                "centaur-tabs-interactive\\.el\\'"))
    (add-to-list 'native-comp-jit-compilation-deny-list re)))
