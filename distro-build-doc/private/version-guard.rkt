#lang racket/base
(require (for-syntax racket/base
                     version/utils))

;; Workaround for a mismatch in the v8.17 inclusion of "distro-build-lib"
;; but not "distro-build-doc" in the distribution's package set

(provide version-guard)

(define-syntax (version-guard stx)
  (if (version<? (version) "8.17.0.1")
      #'(begin)
      (syntax-case stx ()
        [(_ e ...)
         #'(begin e ...)])))
