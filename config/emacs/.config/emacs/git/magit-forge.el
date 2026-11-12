;; -*- lexical-binding: t -*-
;;; git/magit-forge.el --- Forge: issues and pull requests in magit (#6)

;; Forge extends magit-status with issues and pull requests for a repository's
;; host (GitHub, GitLab, ...). After this loads, authenticate once per project:
;;
;;   M-x forge-add-repository      (or `N r' / `'' r' in a magit buffer)
;;
;; Forge reads the API token from ~/.authinfo.gpg, e.g.
;;   machine api.github.com login <user>^forge password <token>

(use-package forge
  :straight t
  :commands (forge-add-repository forge-dispatch forge-pull forge-visit-topic)
  :init
  ;; Forge installs its magit-status sections when it is loaded, and needs
  ;; magit already loaded to do so, so it is loaded together with magit rather
  ;; than lazily on first command.
  (with-eval-after-load 'magit
    (require 'forge)))
