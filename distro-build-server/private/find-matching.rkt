#lang racket/base

(provide find-matching)

(define (find-matching name table)
  (define min-name (string-append
                    "{2} Minimal Racket |"
                    (regexp-replace #rx"[^|]+[|]" name "")))
  (define min-name-tarball (string-append
                            min-name
                            " | {3} Tarball"))
  (define min-name-libs (regexp-replace "built packages"
                                        min-name
                                        "built libraries"))
  (cond
    [(hash-has-key? table min-name-tarball) min-name-tarball]
    [(hash-has-key? table min-name) min-name]
    [(hash-has-key? table min-name-libs) min-name-libs]
    [else #f]))
