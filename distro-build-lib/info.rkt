#lang info

(define collection 'multi)

(define deps '("distro-build-client"
               "distro-build-server"))
(define implies '("distro-build-client"
                  "distro-build-server"))

(define pkg-desc "implementation (no documentation) part of \"distro-build\"")

(define pkg-authors '(mflatt))

(define license
  '(Apache-2.0 OR MIT))
