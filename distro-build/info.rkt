#lang info

(define collection 'multi)

(define deps '("distro-build-lib"
               "distro-build-doc"))
(define implies '("distro-build-lib"
                  "distro-build-doc"))

(define pkg-desc "Tools for constructing a distribution of Racket")

(define pkg-authors '(mflatt))
