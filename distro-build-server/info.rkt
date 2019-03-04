#lang info

(define collection "distro-build")

(define version "1.3")

(define deps '(["base" #:version "6.1.1.6"]
               "distro-build-client"
               "web-server-lib"
               "ds-store-lib"
               "net-lib"
               "scribble-html-lib"
               "plt-web-lib"
               "remote-shell-lib"))
(define build-deps '("at-exp-lib"
                     "rackunit-lib"))

(define pkg-desc "server-side part of \"distro-build\"")

(define pkg-authors '(mflatt))
