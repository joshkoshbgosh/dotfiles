;;; lifeos-task-export-test.el --- isolated task export tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'lifeos-task-export)
(defvar supertag--initialized)

(ert-deftest lifeos-task-export-refuses-uninitialized-store ()
  (let ((supertag--initialized nil))
    (should-error (my/lifeos-export-task-snapshot "/tmp/unused.json" "/tmp" "UTC"))))

(ert-deftest lifeos-task-export-rejects-stale-index-without-writing ()
  (let* ((root (make-temp-file "lifeos-export-" t))
         (source (expand-file-name "task.org" root))
         (output (make-temp-file "lifeos-snapshot-")))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert "* TODO New name #task\n:PROPERTIES:\n:ID: id-1\n:END:\nDEADLINE: <2026-11-09 Mon>\n"))
          (let ((supertag--initialized t))
            (cl-letf (((symbol-function 'supertag-dirty-p) (lambda () nil))
                      ((symbol-function 'supertag-api-query) (lambda (&rest _) '(:truncated nil :count 1 :nodes ((:id "id-1")))))
                      ((symbol-function 'supertag-api-node)
                       (lambda (_) (list :id "id-1" :title "Old name" :file source
                                         :properties '(:ID "id-1")
                                         :tags '((:id "f2d7075f-d8a8-45c0-9e44-40270fb9e99d" :name "task"))))))
              (my/lifeos-export-task-snapshot output root "UTC")))
          (let* ((data (json-parse-string (with-temp-buffer (insert-file-contents output) (buffer-string))
                                          :object-type 'alist :array-type 'list)))
            (should (eq (alist-get 'complete data) :false))
            (should-not (alist-get 'tasks data))))
      (delete-directory root t)
      (delete-file output))))

(ert-deftest lifeos-task-export-empty-query-is-not-proof-of-withdrawal ()
  (let ((root (make-temp-file "lifeos-export-" t))
        (output (make-temp-file "lifeos-snapshot-"))
        (supertag--initialized t))
    (unwind-protect
        (cl-letf (((symbol-function 'supertag-dirty-p) (lambda () nil))
                  ((symbol-function 'supertag-api-query)
                   (lambda (&rest _) '(:truncated nil :count 0 :nodes nil)))
                  ((symbol-function 'supertag-api-node) (lambda (&rest _) nil)))
          (my/lifeos-export-task-snapshot output root "UTC")
          (should (eq :false (alist-get 'complete
                                       (json-parse-string
                                        (with-temp-buffer (insert-file-contents output) (buffer-string))
                                        :object-type 'alist)))))
      (delete-directory root t)
      (delete-file output))))
