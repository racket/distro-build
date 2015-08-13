#lang info

(define collection "distro-build")

(define deps '(["base" #:version "6.2.900.9"]
               "ds-store-lib"))
(define build-deps '("at-exp-lib"))

(define pkg-desc "client-side part of \"distro-build\"")

(define pkg-authors '(mflatt))
