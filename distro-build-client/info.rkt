#lang info

(define collection "distro-build")

(define deps '(["base" #:version "6.2.900.9"]
               ["ds-store-lib" #:version "1.1"]))
(define build-deps '("at-exp-lib"))

(define pkg-desc "client-side part of \"distro-build\"")

(define pkg-authors '(mflatt))

(define license
  '(Apache-2.0 OR MIT))
