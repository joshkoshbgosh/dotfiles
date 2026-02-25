;;; early-init.el --- early startup tweaks -*- lexical-binding: t; -*-

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
