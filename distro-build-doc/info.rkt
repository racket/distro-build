#lang info

(define collection "distro-build")

(define deps '(["base" #:version "6.1.1.6"]
               "distro-build-server"
               "distro-build-client"
               "web-server-lib"))
(define build-deps '("at-exp-lib"
                     "racket-doc"
                     "scribble-lib"))

(define pkg-desc "documentation part of \"distro-build\"")

(define pkg-authors '(mflatt))

(define scribblings '(("distro-build.scrbl" (multi-page))))
