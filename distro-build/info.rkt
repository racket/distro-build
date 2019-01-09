#lang info

(define collection 'multi)

(define version "1.2")

(define deps '("distro-build-lib"
               "distro-build-doc"))
(define implies '("distro-build-lib"
                  "distro-build-doc"))

(define pkg-desc "Tools for constructing a distribution of Racket")

(define pkg-authors '(mflatt))
