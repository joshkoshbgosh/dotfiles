;; -*- lexical-binding: t -*-
;;; files/remoto.el — browse GitHub/Codeberg repositories without cloning

;; remoto registers a `file-name-handler-alist' entry, so `/gh:owner/repo/...'
;; and `/cb:owner/repo/...' paths work in `find-file', Dired, completion,
;; project.el and Embark exactly like local ones.  Nothing is cloned and no
;; shell runs: the tree comes from one API call, file contents on demand, and
;; both are cached (contents by SHA).
;;
;; Read-only by design: no commits, no grep/ripgrep, no compile.  In-buffer
;; search works on files you have opened.
;;
;; Auth is optional for public repositories, but GitHub allows only 60
;; unauthenticated requests an hour, which normal browsing exhausts.  A token
;; comes from auth-source (`machine github.com login USER password TOKEN') or
;; `M-x remoto-login'; forge already reads the same source, so nothing extra is
;; configured here.
;;
;; Entry point: `C-c B' (`remoto-browse'), which accepts a URL, an ssh remote
;; or `owner/repo'.  Loading is deferred on purpose: the package is one 255 KB
;; file plus ghub and costs about 0.2 s to load, which is a fifth of this
;; config's startup for something used occasionally.  The autoloaded
;; `file-name-handler-alist' bootstrap covers `/gh:'/`/cb:' typed at any file
;; prompt, and both routes call `remoto--ensure-global-mode', so the mode
;; switches itself on at first use.  If you would rather not see that one-time
;; echo-area note, add `(global-remoto-mode 1)' after this :commands line and
;; accept the eager load.

(use-package remoto
  :straight t
  :commands (remoto-browse))

;; --- dirvish interop ---
;; Dirvish advises `dired-noselect' and sends every path for which
;; `file-remote-p' is non-nil to `dirvish-tramp-noselect'.  remoto answers
;; `file-remote-p' with its own prefix (so `recentf' and `auto-revert' keep
;; their hands off these buffers) even though it is not TRAMP at all, so
;; dirvish would try to dissect `/gh:owner/repo' as a TRAMP name and fail with
;; "Not a Tramp file name" before remoto's handler sees it.
;;
;; A remote path that is not a TRAMP path has no business in dirvish's TRAMP
;; backend, so hand those to plain dired.  The advice runs on dirvish's advice
;; function, hence the shifted arguments: the first element is the original
;; `dired-noselect' and the rest are its (DIR FLAGS) arguments.
(defun my/dirvish-skip-non-tramp (orig &rest args)
  "Let plain dired handle remote paths that are not TRAMP paths."
  (pcase-let ((`(,dired-fn ,dir . ,rest) args))
    (if (and (functionp dired-fn)
             (stringp dir)
             (file-remote-p dir)
             ;; `file-remote-p' above autoloads TRAMP for a real TRAMP name,
             ;; so an unbound `tramp-tramp-file-p' means it is not one.
             (not (and (fboundp 'tramp-tramp-file-p)
                       (tramp-tramp-file-p dir))))
        (funcall dired-fn dir (car rest))
      (apply orig args))))

(with-eval-after-load 'dirvish
  (advice-add 'dirvish-dired-noselect-a :around #'my/dirvish-skip-non-tramp))
