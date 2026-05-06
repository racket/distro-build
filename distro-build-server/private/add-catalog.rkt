#lang racket/base

(provide add-catalogs)

(define (add-catalogs cross-dir cats #:keep-old? [keep-old? #t])
  (define config-dir (build-path cross-dir "etc"))
  (define config-file (build-path config-dir "config.rktd"))

  (define ht (call-with-input-file* config-file read))

  (define old-catalogs (or (hash-ref ht 'old-catalogs #f)
                           (hash-ref ht 'catalogs '(#f))))
  (let* ([ht (hash-set ht 'catalogs (append (for/list ([cat (in-list cats)])
                                              (if (path? cat)
                                                  (path->string cat)
                                                  cat))
                                            old-catalogs))]
         [ht (if keep-old?
                 (hash-set ht 'old-catalogs old-catalogs)
                 (hash-remove ht 'old-catalogs))])
    (call-with-output-file*
     config-file
     #:exists 'truncate
     (lambda (o) (writeln ht o))))

  old-catalogs)
