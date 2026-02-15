;;; early-init.el --- early startup tweaks -*- lexical-binding: t; -*-

;; Faster startup / less UI junk early
(setq package-enable-at-startup nil)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(setq inhibit-startup-screen t)

;; Reduce GC during startup (we'll restore later)
(setq gc-cons-threshold (* 128 1024 1024)
      gc-cons-percentage 0.6)

;; Native compilation warnings can be noisy on some setups
;; (setq native-comp-async-report-warnings-errors 'silent)
