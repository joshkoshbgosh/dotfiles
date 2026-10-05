;; -*- lexical-binding: t -*-
;;; startup/treesit.el --- predicate-strip advice for libtree-sitter incompatibility
;; Must load before any package (e.g. persp-mode) restores .ts/.tsx buffers.

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 32 1024 1024)
                  gc-cons-percentage 0.2)))

;; Fix for Wayland resize issues in native GUI Emacs frames
(setq inhibit-compacting-font-caches t)

;; NOTE: redraw-display on window-configuration-change-hook removed —
;; it caused a redisplay feedback loop with dirvish preview windows,
;; producing constant "wrong-type-argument number-or-marker-p nil" errors
;; and severe navigation lag.

;; Emacs 30.2 + libtree-sitter >= 0.25 are mutually incompatible on predicates:
;; libtree-sitter now requires a `?' suffix (`#match?'), but Emacs's C-side
;; serializer/runtime still uses the bare form (`#match').  Neither end accepts
;; the other's spelling, and there's no in-Lisp way to bridge them.  As a
;; degraded workaround, strip top-level patterns that use :match/:equal/:pred
;; before compiling.  Built-in modes that use these (typescript-ts-mode's
;; `constant' / `number' features) always pair the predicate-bearing pattern
;; with non-predicate alternatives, so other highlighting still works; only
;; the predicate-gated cases (e.g. ALL_CAPS-as-constant, NaN/Infinity) are lost.
;; Must run before any package (e.g. persp-mode) restores .ts/.tsx buffers,
;; which would otherwise compile and cache the broken queries.
(require 'cl-lib)
(defun my/treesit-pattern-has-predicate-p (form)
  (cond ((memq form '(:match :equal :pred)) t)
        ((consp form)
         (or (my/treesit-pattern-has-predicate-p (car form))
             (my/treesit-pattern-has-predicate-p (cdr form))))))
(define-advice treesit-query-compile
    (:around (orig lang query &optional eager) my/strip-broken-predicates)
  (let ((q query))
    (when (and (consp q) (not (stringp q)))
      (let ((cleaned (cl-remove-if #'my/treesit-pattern-has-predicate-p q)))
        (when cleaned (setq q cleaned))))
    (funcall orig lang q eager)))

