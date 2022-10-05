#lang racket
(require remote-shell/ssh
         remote-shell/docker
         net/url
         racket/date
         file/zip
         pkg/lib
         web-server/servlet-env
         racket/cmdline
         racket/format
         version/utils)

(module test racket/base)

(define installer-vers (version))
(define work-dir (if (directory-exists? "/tmp")
                     ;; Using "/tmp" helps with Docker on Mac OS
                     "/tmp/unix-install-test"
                     (build-path (find-system-path 'temp-dir)
                                 "unix-install-test")))
(define snapshot-site "https://pre-release.racket-lang.org/")
(define remote-pkg "bloggy")
(define pkg-no-verify? #f)

(command-line
 #:once-each
 [("--version") vers "Version to download and install"
                (set! installer-vers vers)]
 [("--work") dir "Set working directory for installers, catalog, etc."
             (set! work-dir dir)]
 [("--site") url "Download from <url>"
             (set! snapshot-site url)]
 [("--pkg") pkg "Try installing <pkg> from the default catalog; empty means none"
            (set! remote-pkg (and (not (string=? pkg"")) pkg))]
 [("--ssl-no-verify") "Skip SSL verification for package-install check"
                      (set! pkg-no-verify? #t)])

;; ----------------------------------------
;; Configuration (adjust as needed)

(define docker-image-name "racket/distro-build:x86_64-linux")

;; Created/replaced/deleted:
(define docker-container-name "unix-installer-test")

;; Working directory in Docker container:
(define docker-dir "/home/racket")

(define installers-site (~a snapshot-site "installers/"))
(define catalog (~a snapshot-site "catalog/"))

(define min-racket-installers
  (list (~a "racket-minimal-" installer-vers "-x86_64-linux.sh")))

(define racket-installers
  (list (~a "racket-" installer-vers "-x86_64-linux.sh")))

(define min-racket-natipkg-installers
  (list (~a "racket-minimal-" installer-vers "-x86_64-linux-natipkg.sh")))

(define racket-src-built-installers
  (list (~a "racket-" installer-vers "-src-builtpkgs.tgz")))

(define min-racket-src-installers
  (list (~a "racket-minimal-" installer-vers "-src.tgz")))

(define min-racket-src-built-installers
  (list (~a "racket-minimal-" installer-vers "-src-builtpkgs.tgz")))

(define (min-needs-base?)
  (version<? installer-vers "8.3.900"))

(define remote-adjust
  (if pkg-no-verify?
      "env PLT_PKG_SSL_NO_VERIFY=y "
      ""))

;; For disabling some tests:
(define basic? #t)
(define natipkg? #t)
(define from-src? #t)

;; ----------------------------------------
;; Create working directory

(unless (directory-exists? work-dir)
  (make-directory work-dir))

;; ----------------------------------------
;; Get installers and "base.zip" from snapshot

(define (get f #:sub [sub ""])
  (unless (file-exists? (build-path work-dir f))
    (printf "Getting ~a\n" f)
    (let ([i (get-pure-port (string->url (string-append installers-site sub f))
                            #:redirections 5)])
      (call-with-output-file*
       (build-path work-dir f)
       #:exists 'truncate
       (lambda (o)
         (copy-port i o)))
      (close-input-port i))))

(for-each get min-racket-installers)
(for-each get racket-installers)
(when natipkg?
  (for-each get min-racket-natipkg-installers))
(when from-src?
  (for-each get (append racket-src-built-installers
                        min-racket-src-installers
                        min-racket-src-built-installers)))
(get #:sub "../pkgs/" "base.zip")

;; ----------------------------------------
;; Construct a simple package

(define sample-pkg-dir (build-path work-dir "sample"))
(delete-directory/files sample-pkg-dir #:must-exist? #f)
(make-directory* sample-pkg-dir)
(call-with-output-file* 
 (build-path sample-pkg-dir "info.rkt")
 (lambda (o)
   (displayln "#lang info" o)
   (write '(define collection "sample") o)
   (write '(define deps '("base")) o)))
(call-with-output-file* 
 (build-path sample-pkg-dir "main.rkt")
 (lambda (o)
   (displayln "#lang racket/base" o)
   (write "sample" o)))

(define sample-zip-path (build-path work-dir "sample.zip"))
(parameterize ([current-directory work-dir])
  (when (file-exists? "sample.zip") (delete-file "sample.zip"))
  (zip "sample.zip" "sample" #:utc-timestamps? #t))

;; ----------------------------------------
;; Construct a simple program

(define progy-path (build-path work-dir "progy.rkt"))
(call-with-output-file*
 progy-path
 #:exists 'truncate
 (lambda (o)
   (displayln "#lang racket/base" o)
   (write '(require sample) o)))


;; ----------------------------------------
;; Packages to local

(define pkg-archive-dir (build-path work-dir "archive"))

(when (or natipkg? from-src?)
  (pkg-catalog-archive pkg-archive-dir
                       (list catalog)
                       #:state-catalog (build-path work-dir "archive" "state.sqlite")
                       #:relative-sources? #t))

;; ----------------------------------------

(define (make-docker-setup #:volumes volumes)
  (lambda ()
    (docker-create #:name docker-container-name
                   #:image-name docker-image-name
                   #:volumes volumes
                   #:replace? #t)
    (docker-start #:name docker-container-name)))

(define docker-teardown
  (lambda ()
    (when (docker-running? #:name docker-container-name)
      (docker-stop #:name docker-container-name))
    (docker-remove #:name docker-container-name)))

(define (at-docker-remote rt path)
  (at-remote rt (string-append docker-dir "/" path)))

;; ----------------------------------------

(when basic?
  (for* ([min? '(#t #f)]
         [f (in-list (if min?
                         min-racket-installers
                         racket-installers))]
         ;; Unix-style install?
         [unix-style? '(#f #t)]
         ;; Change path of "shared" to "mine-all-mine"?
         [mv-shared? (if unix-style? '(#t #f) '(#f))]
         ;; Install into "/usr/local"?
         [usr-local? '(#t #f)]
         ;; Link in-place install executables in "/usr/local/bin"?
         [links? (if unix-style? '(#f) '(#t #f))])
    (printf (~a "=================================================================\n"
                "CONFIGURATION: "
                (if min? "minimal" "full") " "
                (if unix-style? "unix-style" "in-place") " "
                (if mv-shared? "mine-all-mine " "")
                (if usr-local? "/usr/local " "")
                (if links? "linked" "")
                "\n"))
    (define need-base? (and min? (min-needs-base?)))

    (#%app
     dynamic-wind

     (make-docker-setup #:volumes '())
     
     (lambda ()
       (define rt (remote #:host docker-container-name
                          #:kind 'docker))
       
       (scp rt (build-path work-dir f) (at-docker-remote rt f))

       (define script (build-path work-dir "script"))
       (call-with-output-file*
        script
        #:exists 'truncate
        (lambda (o)
          ;; Installer interactions:
          ;; 
          ;; Unix-style distribution?
          ;;  * yes -> 
          ;;     Where to install?
          ;;       [like below]
          ;; 
          ;;     Target directories
          ;;       [e]
          ;;       ...
          ;; 
          ;;  * no ->  
          ;;     Where to install?
          ;;       * 1 /usr/racket
          ;;       * 2 /usr/local/racket
          ;;       * 3 ~/racket
          ;;       * 4 ./racket
          ;;       * <anything else>
          ;; 
          ;;     Prefix for link?
          (fprintf o "~a\n" (if unix-style? "yes" "no"))
          (fprintf o (if usr-local?
                         "2\n"
                         "4\n"))
          (when mv-shared?
            (fprintf o "s\n") ; "shared" path
            (fprintf o "~a\n" (if usr-local?
                                  "/usr/local/mine-all-mine"
                                  "mine-all-mine")))
          (when links?
            (fprintf o "/usr/local\n"))
          (fprintf o "\n")))
       (scp rt script (at-docker-remote rt "script"))

       (when need-base?
         (scp rt (build-path work-dir "base.zip") (at-docker-remote rt "base.zip")))
       (scp rt sample-zip-path (at-docker-remote rt "sample.zip"))
       (unless min?
         (scp rt progy-path (at-docker-remote rt "progy.rkt")))

       (define sudo? (or usr-local? links?))
       (define sudo (if sudo? "sudo " ""))

       ;; install --------------------
       (ssh rt sudo "sh " f " < script")

       (define bin-dir
         (cond
          [(or links? (and usr-local? unix-style?)) ""]
          [else
           (~a (if usr-local?
                   "/usr/local/"
                   "")
               (if unix-style?
                   "bin/"
                   "racket/bin/"))]))

       ;; check that Racket runs --------------------
       (ssh rt (~a bin-dir "racket") " -e '(displayln \"hello\")'")

       ;; check that `raco setup` is ok --------------------
       ;;  For example, there are no file-permission problems.
       (ssh rt (~a bin-dir "raco") " setup" (if sudo?
                                                " --avoid-main"
                                                ""))

       ;; install and use a package --------------------
       (ssh rt (~a bin-dir "raco") " pkg install sample.zip" (if need-base? " base.zip" ""))
       (ssh rt (~a bin-dir "racket") " -l sample")

       ;; install a package from the package server --------------------
       (when remote-pkg
         (ssh rt remote-adjust (~a bin-dir "raco") " pkg install " remote-pkg))

       ;; create a stand-alone executable ----------------------------------------
       (unless min?
         (ssh rt (~a bin-dir "raco") " exe progy.rkt")
         (ssh rt "./progy")
         (ssh rt (~a bin-dir "raco") " distribute d progy")
         (ssh rt "d/bin/progy"))

       ;; uninstall ----------------------------------------
       (when unix-style?
         (ssh rt sudo (~a bin-dir "racket-uninstall"))
         (when (ssh rt (~a bin-dir "racket") #:mode 'result)
           (error "not uninstalled")))

       ;; check stand-alone executable ----------------------------------------
       (unless min?
         (ssh rt "d/bin/progy"))
       
       (void))

     docker-teardown)))

;; ----------------------------------------

(when natipkg?
  (sync (system-idle-evt))
  
  (for* ([f (in-list min-racket-natipkg-installers)])
    (printf (~a "=================================================================\n"
                "NATIPKG: "
                f
                "\n"))

    (#%app
     dynamic-wind
     
     (make-docker-setup #:volumes `((,pkg-archive-dir "/archive" ro)))
     
     (lambda ()
       (define rt (remote #:host docker-container-name
                          #:kind 'docker))
       
       (scp rt (build-path work-dir f) (at-docker-remote rt f))

       ;; install --------------------
       (ssh rt "sh " f " --in-place --dest racket")

       (define bin-dir "racket/bin/")

       ;; check that Racket runs --------------------
       (ssh rt (~a bin-dir "racket") " -e '(displayln \"hello\")'")

       ;; check that `raco setup` is ok --------------------
       (ssh rt (~a bin-dir "raco") " setup")

       ;; install packages  --------------------
       (ssh rt (~a bin-dir "raco") " pkg install"
            " --recompile-only"
            " --catalog /archive/catalog/"
            " --auto"
            " drracket")
       
       ;; check that the drawing library works:
       (ssh rt (~a bin-dir "racket") " -l racket/draw")

       ;; install a package from the package server --------------------
       (when remote-pkg
         (ssh rt remote-adjust (~a bin-dir "raco") " pkg install " remote-pkg))

       (void))

     docker-teardown)))

;; ----------------------------------------

(when from-src?
  (sync (system-idle-evt))

  (for* ([mode '(min-src min-src-built src-built)]
         [f (in-list (case mode
                       [(min-src)
                        min-racket-src-installers]
                       [(min-src-built)
                        min-racket-src-built-installers]
                       [(src-built)
                        racket-src-built-installers]))]
         [prefix? '(#f #t)]
         [cs? '(#f #t)])
    (define built? (not (eq? mode 'min-src)))
    (define min? (not (eq? mode 'src-built)))
    (define need-base? (and min? (min-needs-base?)))
    
    (printf (~a "=================================================================\n"
                "SOURCE: "
                f
                (if cs? " CS" " BC")
                (if prefix? " --prefix" "")
                "\n"))

  
    (#%app
     dynamic-wind
     
     (make-docker-setup #:volumes `((,pkg-archive-dir "/archive" ro)))
     
     (lambda ()
       (define rt (remote #:host docker-container-name
                          #:kind 'docker
                          #:timeout (if cs? 1500 600)))

       (scp rt (build-path work-dir f) (at-docker-remote rt f))

       ;; build --------------------
       (ssh rt "tar zxf " f)

       (define racket-dir (~a "racket-" installer-vers "/"))

       (ssh rt (~a "cd " racket-dir "src "
                   " && mkdir build"
                   " && cd build"
                   " && ../configure" (~a (if prefix?
                                              (~a " --prefix=" docker-dir "/local")
                                              "")
                                          (if cs?
                                              " --enable-csdefault"
                                              " --enable-bcdefault"))
                   " && make -j 2"
                   " && make install" (~a (if built?
                                              " PLT_SETUP_OPTIONS=--recompile-only"
                                              ""))))

       (define bin-dir (if prefix?
                           "local/bin/"
                           (~a racket-dir "bin/")))

       ;; check that Racket runs --------------------
       (ssh rt (~a bin-dir "racket") " -e '(displayln \"hello\")'")

       ;; check that `raco setup` is ok --------------------
       (ssh rt (~a bin-dir "raco") " setup")

       ;; if starting from min and built, install DrRacket ------------
       (when (and min? built?)
         (ssh rt (~a bin-dir "raco") " pkg install"
              " --recompile-only"
              " --catalog /archive/catalog/"
              " --auto"
              " drracket"))
       
       ;; install a package from the package server --------------------
       (when remote-pkg
         (when (and need-base? (not built?))
           (ssh rt (~a bin-dir "raco") " pkg install"
                " --recompile-only"
                " --catalog /archive/catalog/"
                " --auto"
                " base"))
         (ssh rt remote-adjust (~a bin-dir "raco") " pkg install " remote-pkg))

       (void))

     docker-teardown)))
