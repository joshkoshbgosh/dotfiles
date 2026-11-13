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

;; Cap async native-compilation workers.  The default is half the CPUs (6
;; here), which on the first start after an Emacs upgrade gathers every
;; package .eln at once and makes the UI crawl until the queue drains.  A
;; warm cache is unaffected; this only bounds first-run cost.
(setq native-comp-async-jobs-number 4)

;; Silence noisy upstream native-comp warnings from packages we don't patch.
(when (boundp 'native-comp-jit-compilation-deny-list)
  (dolist (re '("general\\.el\\'"
                "centaur-tabs-interactive\\.el\\'"))
    (add-to-list 'native-comp-jit-compilation-deny-list re)))
