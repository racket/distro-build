#lang info

(define collection "distro-build")

(define pkg-desc "Distribution-build tests")

(define deps '("base"))
(define build-deps '("remote-shell-lib"
                     "web-server-lib"))

(define pkg-authors '(mflatt))
