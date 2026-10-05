;; -*- lexical-binding: t -*-
;;; themes/fonts.el — Font, theme-switching, and chrome helpers

(setq-default line-spacing 0.0)

(defun my/font-set (family height)
  "Set default font FAMILY at HEIGHT (1/10 pt)."
  (set-face-attribute 'default nil :family family :height height))

(defun my/font-bigger ()
  (interactive)
  (set-face-attribute 'default nil :height (+ (face-attribute 'default :height) 10)))

(defun my/font-smaller ()
  (interactive)
  (set-face-attribute 'default nil :height (- (face-attribute 'default 'height) 10)))

(defun my/toggle-fullscreen ()
  "Toggle between full-screen and maximized window."
  (interactive)
  (if (frame-parameter nil 'fullscreen)
      (set-frame-parameter nil 'fullscreen 'maximized)
    (set-frame-parameter nil 'fullscreen 'fullboth)))

;; Bigger text + more breathing room
(set-face-attribute 'default nil :family "JetBrainsMono Nerd Font" :height 160)
(setq-default line-spacing 0.15)
(set-fringe-mode 16)


