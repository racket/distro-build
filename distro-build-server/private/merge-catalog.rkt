#lang racket/base
(require racket/file)

(provide merge-catalog)

(define (merge-catalog version base-dir extra-base-dir dest)
  (define who 'merge-catalogs)
  (define site-dir (build-path base-dir dest))
  (define extra-site-dir (build-path extra-base-dir dest))
  (define catalog-dir (build-path site-dir "catalog"))
  (define extra-catalog-dir (build-path extra-site-dir "catalog"))

  (define pkgs-all-file (build-path catalog-dir "pkgs-all"))
  (define pkgs-all (with-input-from-file pkgs-all-file read))
  (define extra-pkgs-all (call-with-input-file* (build-path extra-catalog-dir "pkgs-all") read))

  (define (move-path p)
    (define elems (explode-path p))
    (path->string (apply build-path (car elems) version (cdr elems))))

  (define (merge-version ht extra-ht)
    (define sub-ht (hash-ref ht 'versions #hash()))
    (define new-sub-ht (hash-set sub-ht
                                 version
                                 (for/hash ([(k raw-v) (in-hash extra-ht)]
                                            #:do [(define v (if (eq? k 'source)
                                                                (move-path raw-v)
                                                                raw-v))]
                                            #:unless (equal? v (hash-ref ht k #f)))
                                   (values k v))))
    (hash-set ht 'versions new-sub-ht))

  (define new-pkgs-all
    (for/fold ([pkgs-all pkgs-all]) ([(pkg extra-ht) (in-hash extra-pkgs-all)])
      (define ht (hash-ref pkgs-all pkg #f))
      (unless ht
        (error who "package in extra version, not in main version: ~s" pkg))
      (define pkg-file (build-path catalog-dir "pkg" pkg))
      (unless (equal? ht (call-with-input-file* pkg-file read))
        (error who "mismatch between \"pkgs-all\" and \"pkg/~a\"" pkg))
      (define new-ht (merge-version ht extra-ht))
      (call-with-output-file* pkg-file #:exists 'truncate (lambda (o) (writeln new-ht o)))
      (hash-set pkgs-all pkg new-ht)))

  (call-with-output-file* pkgs-all-file
                          #:exists 'truncate
                          (lambda (o) (writeln new-pkgs-all o)))

  (define pkgs-dest (build-path site-dir version "pkgs"))
  (define extra-pkgs-dest (build-path extra-site-dir "pkgs"))
  (make-directory* pkgs-dest)
  (for ([f (in-list (directory-list extra-pkgs-dest))])
    (when (file-exists? (build-path extra-pkgs-dest f))
      (copy-file (build-path extra-pkgs-dest f) (build-path pkgs-dest f)
                 #:exists-ok? #t))))
