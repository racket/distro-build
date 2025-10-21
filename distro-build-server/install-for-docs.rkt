#lang racket/base
(require racket/cmdline
         racket/file
         racket/string
         racket/system
         racket/list
         racket/format
         compiler/find-exe
         file/untgz
         setup/dirs
         (only-in "config.rkt" extract-options)
         distro-build/display-time
         remote-shell/docker
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

(define doc-vm (hash-ref config '#:doc-vm #f))

(define use-docker? doc-vm)

(define docker-dir (and doc-vm (hash-ref doc-vm 'dir "build")))
(define docker-name (and doc-vm (hash-ref doc-vm 'name "distro-build-doc")))
(define docker-image-name (and doc-vm (hash-ref doc-vm 'image-name "racket/distro-build-doc")))
(define docker-installer (and doc-vm
                              (regexp-replace* "VERSION"
                                               (hash-ref doc-vm 'installer "racket-VERSION.sh")
                                               (version))))
(define docker-mnt-dir "/docker-mnt")

(unless use-docker?
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

  ;; If the same build directory was used for an installer client,
  ;; then the main "collects" directory can have the wrong sort
  ;; of compiled files in place. Unpack the old "collects.tgz"
  ;; to make sure it's in sync
  (define tgz-file (build-path "build" "origin" "collects.tgz"))
  (when (file-exists? tgz-file)
    (call-with-input-file*
     tgz-file
     (lambda (i)
       (untgz i #:dest "racket")))))

(define (command . s) (apply string-append (add-between s " ")))
(define (build-path/string base f) (path->string (build-path base f)))

(when use-docker?
  (display-time #:server? #t)
  (printf "Preparing Docker container: ~a\n" docker-name)
  (flush-output)
  (make-directory* dir)
  (file-or-directory-permissions dir #o777) ; world-writeable so Docker user ID matters less
  (docker-create #:name docker-name
                 #:replace? #t
                 #:image-name docker-image-name
                 #:volumes (append
                            (list
                             (list (path->complete-path dir)
                                   (format "~a/output" docker-mnt-dir)
                                   'rw))
                            (list
                             (list (path->complete-path "build/installers")
                                   (format "~a/installers" docker-mnt-dir)
                                   'ro))
                            (for/list ([catalog (in-list catalogs)]
                                       [i (in-naturals)]
                                       #:when (directory-exists? catalog))
                              (list (path->complete-path catalog)
                                    (format "~a/catalog~a" docker-mnt-dir i)
                                    'ro))))

  (docker-start #:name docker-name))

(define (stop-container)
  (when use-docker?
    (docker-stop #:name docker-name)))

(with-handlers ([exn? (lambda (exn)
                        ((error-display-handler) (exn-message exn) exn)
                        (stop-container))])
  (when use-docker?
    (display-time #:server? #t)
    (printf "Installing ~a in container\n" docker-installer)
    (flush-output)
    (docker-exec #:name docker-name
                 "/bin/sh" "-c"
                 (command "mkdir -p" docker-dir
                          "&& cd" docker-dir
                          "&& sh" (~a docker-mnt-dir "/installers/" docker-installer)
                          "--in-place --dest racket")))

  (display-time #:server? #t)
  (printf "Running `raco pkg install' for packages:\n")
  (for ([pkg (in-list pkgs)])
    (printf "  ~a\n" pkg))
  (flush-output)

  (define system*-or-docker
    (if use-docker?
        (lambda (exe . args)
          (docker-exec #:name docker-name
                       "/bin/sh" "-c"
                       (apply command
                              (build-path/string docker-dir "racket/bin/racket")
                              args)))
        system*))

  (unless (apply system*-or-docker (find-exe)
                 (append
                  (if use-docker?
                      null
                      (append
                       (list "-G" "build/docs/etc")
                       (target-machine-flags)))
                  (list
                   "-l-" "raco" "pkg" "install"
                   "--pkgs"
                   "-i" "--deps" "search-auto"
                   "--recompile-only"
                   "--skip-installed")
                  (if use-docker?
                      (apply append
                             (for/list ([catalog (in-list catalogs)]
                                        [i (in-naturals)]
                                        #:when (directory-exists? catalog))
                               (list "--catalog" (format "~a/catalog~a" docker-mnt-dir i))))
                      null)
                  pkgs))
    (error "install failed"))

  (when (hash-ref config '#:pdf-doc? #f)
    (display-time #:server? #t)
    (printf "Running `raco setup' PDF documentation:\n")
    (flush-output)
    (unless (apply system*-or-docker (find-exe)
                   (append
                    (if use-docker?
                        null
                        (append
                         (list "-G" "build/docs/etc")
                         (target-machine-flags)))
                    (list
                     "-l-" "raco" "setup"
                     "--recompile-only"
                     "--doc-pdf" (if use-docker?
                                     (build-path/string docker-dir "pdf-doc")
                                     "build/pdf-doc"))))
      (error "PDF failed")))

  (when use-docker?
    (printf "Gathering documentation\n")
    (flush-output)
    (docker-exec #:name docker-name
                 "/bin/sh" "-c"
                 (command "cd" (build-path/string docker-dir "racket")
                          "&& tar zcf"
                          (format "~a/output/doc.tgz" docker-mnt-dir)
                          "doc"))
    (when (hash-ref config '#:pdf-doc? #f)
      (docker-exec #:name docker-name
                   "/bin/sh" "-c"
                   (command "cd" docker-dir
                            "&& tar zcf"
                            (format "~a/output/pdf-doc.tgz" docker-mnt-dir)
                            "pdf-doc")))
    (define tar-exe (or (find-executable-path "tar")
                        (error "could not find `tar` executable")))
    (parameterize ([current-directory dir])
      (unless (system* tar-exe "zxf" "doc.tgz")
        (error "doc packing failed")))
    (when (hash-ref config '#:pdf-doc? #f)
      (let ([dir (path->complete-path dir)])
        (parameterize ([current-directory "build"])
          (unless (system* tar-exe "zxf" (build-path dir "pdf-doc.tgz"))
            (error "PDF doc packing failed"))))))

  (display-time #:server? #t)
  (stop-container))
