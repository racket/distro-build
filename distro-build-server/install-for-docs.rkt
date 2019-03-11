#lang racket/base
(require racket/cmdline
         racket/file
         racket/string
         racket/system
         compiler/find-exe
         setup/dirs
         (only-in "config.rkt" extract-options)
         distro-build/display-time
         "private/target-machine.rkt")

(module test racket/base)

(define-values (dir config-file config-mode default-pkgs catalogs)
  (command-line
   #:args
   (dir config-file config-mode default-pkgs . catalog)
   (values dir config-file config-mode default-pkgs catalog)))

(define config (extract-options config-file config-mode))

(define pkgs
  (or (hash-ref config '#:pkgs #f)
      (string-split default-pkgs)))

(define (build-path/s . a)
  (path->string (path->complete-path (apply build-path dir a))))
(define (build-path/f . a)
  (string-append "file://" 
                 (path->string (path->complete-path (apply build-path a)))))

(define ht
  (hash 'doc-dir (build-path/s "doc")
        'lib-dir (build-path/s "lib")
        'share-dir (build-path/s "share")
        'dll-dir (build-path/s "lib")
        'links-file (build-path/s "share" "links.rktd")
        'pkgs-dir (build-path/s "share" "pkgs")
        'bin-dir (build-path/s "bin")
        'include-dir (build-path/s "include")
        'catalogs (map build-path/f catalogs)))

(make-directory* (build-path dir "etc"))

(call-with-output-file*
 (build-path dir "etc" "config.rktd")
 #:exists 'truncate/replace
 (lambda (o)
   (write ht o)
   (newline o)))

;; For -MCR builds to work right, we need "system.rktd" with
;; its mapping of 'target-machine to #f:
(define system.rktd (build-path (find-lib-dir) "system.rktd"))
(when (file-exists? system.rktd)
  (make-directory* (build-path dir "lib"))
  (copy-file system.rktd (build-path dir "lib" "system.rktd")))

(display-time)
(printf "Running `raco pkg install' for packages:\n")
(for ([pkg (in-list pkgs)])
  (printf "  ~a\n" pkg))
(unless (apply system* (find-exe)
               (append
                (list "-G" "build/docs/etc")
                (target-machine-flags)
                (list
                 "-l-" "raco" "pkg" "install"
                 "--pkgs"
                 "-i" "--deps" "search-auto"
                 "--recompile-only")
                pkgs))
  (error "install failed"))

(when (hash-ref config '#:pdf-doc? #f)
  (display-time)
  (printf "Running `raco setup' PDF documentation:\n")
  (unless (apply system* (find-exe)
                 (append
                  (list "-G" "build/docs/etc")
                  (target-machine-flags)
                  (list
                   "-l-" "raco" "setup"
                   "--recompile-only"
                   "--doc-pdf" "build/pdf-doc")))
    (error "PDF failed")))
  
(display-time)
