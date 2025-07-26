#lang racket/base
(require racket/format
         (only-in distro-build/config
                  machine
                  parallel
                  sequential
                  spliceable
                  site-config?
                  site-config-tag
                  site-config-options
                  site-config-content))

(provide make-machines
         make-start-check
         make-site-help
         make-site-help-fallbacks
         make-spliceable-limits

         racket-name
         minimal-racket-name
         racket-file-name
         minimal-racket-file-name

         extract-container-names)

(define on-x86_64? (eq? 'x86_64 (system-type 'arch)))
(define on-aarch64? (eq? 'aarch64 (system-type 'arch)))
(define common (system-type 'arch))

(define (make-start-check)
  (lambda (c)
    (unless (or on-x86_64? on-aarch64?)
      (error "expecting to run on x86_64 or AArch64"))))

;; Whether to cross-build for especially old Raspberry Pi, which
;; currently requires a host that can run an x86_64 Docker image.
(define arm-debian7? (and #f
                          (or on-x86_64?
                              (eq? 'macosx (system-type)))))

(define racket-file-name "racket")
(define minimal-racket-file-name "racket-minimal")

(define windows        "{1} Windows")
(define macosx         "{2} Mac OS")
(define linux          "{3} Linux")
(define unix-platforms "{8} Unix")
(define all-platforms  "{9} All Platforms")

(define disk-image-name " | {1} Disk Image")
(define installer-name  " | {1} Installer")
(define tarball-name    " | {3} Tarball")

(define racket-name         "{1} Racket")
(define minimal-racket-name "{2} Minimal Racket")

(define win64-name "{1} 64-bit x64; for Windows 7 and up")
(define win32-name "{2} 32-bit x86; for Windows 7 and up")
(define winarm64-name "{3} 64-bit Arm; for Windows 10 and up")

(define mac-aarch64-name "{0} 64-bit Apple Silicon; for Mac OS 11 and up")
(define mac-x86_64-name "{1} 64-bit Intel; for Mac OS 10.9 and up")
(define mac-i386-name "{2} 32-bit Intel; for Mac OS 10.6 and up")
(define mac-ppc-name "{2} 32-bit PowerPC; for Mac OS 10.5 and up")

(define debian10-dist-name-suffix "; built on Debian 10")
(define debian10-dist-suffix "buster")

(define debian12-dist-name-suffix "; built on Debian 12")
(define debian12-dist-suffix "jammy") ; using Ubuntu name instead of Debian name "bookworm"

(define natipkg-name-extra " natipkg")
(define pkg-build-name-extra " for pkg-build")

(define linux-extra-aliases '((#f "" #f)))

(define (linux-x86_64-name #:extra [extra ""]
                           #:order [order 1]
                           #:platform [dist-name-suffix debian10-dist-name-suffix])
  (format "~a64-bit x86_64~a~a"
          (if order
              (format "{~a} " order)
              "")
          extra
          dist-name-suffix))

(define (linux-aarch64-name #:platform [dist-name-suffix debian10-dist-name-suffix])
  (format "{3} 64-bit AArch64~a"
          dist-name-suffix))

(define (linux-i386-name #:platform [dist-name-suffix debian10-dist-name-suffix])
  (format "{2} 32-bit i386~a"
          dist-name-suffix))

(define (linux-arm-name)
  "{5} 32-bit ARMv6 VFP; built on Raspbian")

(define (linux-riscv64-name #:platform [dist-name-suffix debian12-dist-name-suffix])
  (format "{6} 64-bit RISC-V~a"
          dist-name-suffix))

(define (machine/tgz #:name name)
   (machine #:name (~a name tarball-name)
            #:tgz? #t))

(define (machine/none #:name name)
  (sequential))

(define (machine/dmg+tgz #:name name)
  ;; Create all Mac installer forms
  (sequential
   (machine #:name (~a name disk-image-name))
   (machine #:name (~a name tarball-name)
            #:tgz? #t
            #:clean? #f)))

(define (make-mac-signed sign-cert-config m)
  (if sign-cert-config
      (sequential
       #:sign-cert-config sign-cert-config
       #:hardened-runtime? #f ; overridden for notarized
       m)
      m))

(define (make-mac-notarized notarization-config m)
  (if notarization-config
      (sequential
       #:hardened-runtime? #t
       #:notarization-config notarization-config
       m)
      m))

(define (make-machine/exe+tgz windows-sign-post-process)
  (lambda (#:name name)
    (sequential
     (machine #:name (~a name installer-name))
     (machine #:name (~a name tarball-name)
              #:tgz? #t
              #:clean? #f
              #:splice (if windows-sign-post-process
                           (spliceable
                            #:server-installer-post-process null)
                           (spliceable))))))

(define (machine/sh+tgz #:name name)
  ;; Create all Linux installer forms
  (sequential
   (machine #:name (~a name installer-name))
   (machine #:name (~a name tarball-name)
            #:tgz? #t
            #:clean? #f)))

(define (merge-aliaes aliases extra-aliases)
  (append
   (if aliases
       (append
        (list '(#f #f ""))
        aliases
        (for/list ([a (in-list extra-aliases)])
          (list (car a) (cadr a) "")))
       null)
   extra-aliases))

(define (cs-machine m
                    #:host host
                    #:container-prefix container-prefix
                    #:as-default-with-aliases [aliases #f]
                    #:extra-aliases [extra-aliases '()])
  (sequential
   #:host (~a container-prefix host "-cs")
   #:variant 'cs
   #:dist-vm-suffix "cs"
   #:dist-aliases (merge-aliaes aliases extra-aliases)
   m))

(define (bc-machine m
                    #:host host
                    #:container-prefix container-prefix
                    #:as-default-with-aliases [aliases #f]
                    #:extra-aliases [extra-aliases '()])
  (sequential
   #:host (~a container-prefix host "-bc")
   #:variant 'bc
   #:dist-vm-suffix "bc"
   #:dist-aliases  (merge-aliaes aliases extra-aliases)
   m))

(define (no-machine m
                    #:host host
                    #:container-prefix container-prefix
                    #:as-default-with-aliases [aliases #f]
                    #:extra-aliases [extra-aliases '()])
  (sequential))

(define (uncommon m)
  m)

(define (no-uncommon m)
  (sequential))

(define (filter-machs filter-rx m)
  (cond
    [(not filter-rx) m]
    [else
     (define default-variant 'cs)
     (define (matches? m)
       (regexp-match? filter-rx (hash-ref (site-config-options m) '#:name
                                          (hash-ref (site-config-options m) '#:host "localhost"))))
     (define (find-keep-commons)
       (let loop ([m m] [variant default-variant] [racket #f] [keep #hash()])
         (define new-variant (or (hash-ref (site-config-options m) '#:variant #f)
                                 variant))
         (define new-racket (or (hash-ref (site-config-options m) '#:racket #f)
                                racket))
         (cond
           [(eq? (site-config-tag m) 'machine)
            (if (and racket
                     (matches? m))
                (hash-set keep (list variant racket) #t)
                keep)]
           [else
            (for/fold ([keep keep]) ([m (in-list (site-config-content m))])
              (loop m new-variant new-racket keep))])))
     (define (filter-machs keep-commons)
       (let loop ([m m] [variant default-variant] [dir #f])
         (define new-variant (or (hash-ref (site-config-options m) '#:variant #f)
                                 variant))
         (define new-dir (or (hash-ref (site-config-options m) '#:dir #f)
                             dir))
         (cond
           [(eq? (site-config-tag m) 'machine)
            (if (or (hash-ref keep-commons (list new-variant new-dir) #f)
                    (matches? m))
                m
                (sequential))]
           [else
            (define kws (sort (hash-keys (site-config-options m)) keyword<?))
            (keyword-apply
             (if (eq? (site-config-tag m) 'sequential) sequential parallel)
             kws
             (for/list ([kw (in-list kws)])
               (hash-ref (site-config-options m) kw))
             (for/list ([m (in-list (site-config-content m))])
               (loop m new-variant new-dir)))])))
     (filter-machs (find-keep-commons))]))

(define (source-machine make-name src-platforms built-desc
                        #:container-prefix container-prefix)
  (sequential
   #:host (~a container-prefix "crosslinux-source")
   #:variant 'cs
   #:compile-any? #t
   (machine
    #:name (make-name src-platforms "Source")
    #:source? #t
    #:dist-suffix "")
   (machine
    #:name (make-name src-platforms "Source with versionless path")
    #:source? #t
    #:versionless? #t
    #:dist-suffix ""
    #:clean? #f)
   (machine
    #:name (make-name src-platforms (string-append "Source + " built-desc))
    #:source-runtime? #t
    #:dist-suffix "builtpkgs"
    #:clean? #f)))

;; Constructor for all machine configurations:
(define (make-machs container-prefix
                    make-cs-name make-bc-name base aliases pkgs
                    src-platforms built-desc
                    win-machine mac-machine linux-machine extra-linux-machine
                    cs-machine bc-machine
                    uncommon
                    windows-sign-post-process
                    mac-sign-cert-config
                    mac-notarization-config
                    recompile-cache
                    natipkg?)
  (define make-name make-cs-name)
  (define (cs+bc-machine machine
                         #:host host
                         #:platform platform
                         #:detail detail
                         #:default [default 'cs]
                         #:extra-aliases [extra-aliases '()]
                         #:bc? [bc? #t])
    (parallel
     (cs-machine
      #:host host
      #:container-prefix container-prefix
      #:as-default-with-aliases (and (eq? default 'cs) aliases)
      #:extra-aliases extra-aliases
      (machine
       #:name (make-cs-name platform detail)))
     (if bc?
         (bc-machine
          #:host host
          #:container-prefix container-prefix
          #:as-default-with-aliases (and (eq? default 'bc) aliases)
          #:extra-aliases extra-aliases
          (machine
           #:name (make-bc-name platform detail)))
         (sequential))))
  (sequential
   #:dist-base base
   #:pkgs pkgs
   #:recompile-cache recompile-cache

   ;; Not an installer, but a host build (relative to a container) to
   ;; create once and share across cross builds
   (parallel
    #:dir common
    #:docker "racket/distro-build:debian10"
    (cs-machine
     #:host "cross-common"
     #:container-prefix container-prefix
     (machine))
    (bc-machine
     #:host "cross-common"
     #:container-prefix container-prefix
     (machine)))

   (parallel
    #:racket common
    ;; ----------------------------------------
    ;; Linux
    (parallel
     #:dist-suffix debian10-dist-suffix
     ;; ----------------------------------------
     ;; Linux x86_64
     (parallel
      #:docker (if on-x86_64?
                   "racket/distro-build:debian10"
                   "racket/distro-build:crosslinux-x86_64")
      #:cross-target-machine (and (not on-x86_64?) "ta6le")
      #:cross-target (and (not on-x86_64?) "x86_64-linux-gnu")
      (cs+bc-machine
       linux-machine
       #:platform linux
       #:detail (linux-x86_64-name)
       #:host "crosslinux-x86_64"
       #:extra-aliases linux-extra-aliases)
      ;; ----------------------------------------
      ;; Source, maybe
      (if on-x86_64?
          (source-machine make-name src-platforms built-desc
                          #:container-prefix container-prefix)
          (sequential)))
     ;; ----------------------------------------
     ;; Linux aarch64
     (parallel
      #:docker (if on-aarch64?
                   "racket/distro-build:debian10"
                   "racket/distro-build:crosslinux-aarch64")
      #:cross-target-machine (and (not on-aarch64?) "tarm64le")
      #:cross-target (and (not on-aarch64?) "aarch64-linux-gnu")
      (cs+bc-machine
       linux-machine
       #:platform linux
       #:detail (linux-aarch64-name)
       #:host "crosslinux-aarch64"
       #:extra-aliases linux-extra-aliases)
      ;; ----------------------------------------
      ;; Source, maybe
      (if on-aarch64?
          (source-machine make-name src-platforms built-desc
                          #:container-prefix container-prefix)
          (sequential)))
     ;; ----------------------------------------
     ;; Linux i386
     (parallel
      #:docker "racket/distro-build:crosslinux-i386"
      #:cross-target-machine "ti3le"
      #:cross-target "i686-linux-gnu"
      (cs+bc-machine
       linux-machine
       #:host "crosslinux-i386"
       #:platform linux
       #:detail (linux-i386-name)
       #:extra-aliases linux-extra-aliases))
     ;; ----------------------------------------
     ;; Linux arm
     (parallel
      #:racket (if arm-debian7? #f common)
      #:docker (if arm-debian7?
                   "racket/distro-build:crosslinux-arm-debian7"
                   "racket/distro-build:crosslinux-arm")
      #:docker-platform (and arm-debian7?
                             "linux/amd64")
      #:cross-target-machine "tarm32le"
      #:cross-target "arm-linux-gnueabihf"
      (cs+bc-machine
       linux-machine
       #:host "crosslinux-arm"
       #:platform linux
       #:detail (linux-arm-name)
       #:extra-aliases linux-extra-aliases))
     ;; ----------------------------------------
     ;; Linux riscv64
     (uncommon
      (parallel
       #:docker "racket/distro-build:crosslinux-riscv64"
       #:cross-target-machine "trv64le"
       #:cross-target "riscv64-linux-gnu"
       #:dist-suffix debian12-dist-suffix
       (cs+bc-machine
        linux-machine
        #:host "crosslinux-riscv64"
        #:platform linux
        #:detail (linux-riscv64-name)
        #:extra-aliases linux-extra-aliases))))
    ;; ----------------------------------------
    ;; Linux Debian 12 / Ubuntu 22
    (parallel
     #:dist-suffix debian12-dist-suffix
     ;; ----------------------------------------
     ;; Linux Debian 12 x86_64
     (parallel
      #:docker "racket/distro-build:debian12"
      #:cross-target-machine (and (not on-x86_64?) "ta6le")
      #:cross-target (and (not on-x86_64?) "x86_64-linux-gnu")
      ;; ----------------------------------------
      ;; CS
      (cs-machine
       #:host "debian12-x86_64"
       #:container-prefix container-prefix
       #:as-default-with-aliases aliases
       (extra-linux-machine
        #:name (make-cs-name linux (linux-x86_64-name #:platform debian12-dist-name-suffix)))))
     ;; ----------------------------------------
     ;; Linux Debian 12 aarch64
     (parallel
      #:docker "racket/distro-build:debian12"
      #:cross-target-machine (and (not on-aarch64?) "tarm64le")
      #:cross-target (and (not on-aarch64?) "aarch64-linux-gnu")
      ;; ----------------------------------------
      ;; CS
      (cs-machine
       #:host "debian12-aarch64"
       #:container-prefix container-prefix
       #:as-default-with-aliases aliases
       (extra-linux-machine
        #:name (make-cs-name linux (linux-aarch64-name #:platform debian12-dist-name-suffix))))))
    ;; ----------------------------------------
    ;; Linux Natipkg
    (if natipkg?
        (parallel
         #:docker (if on-x86_64?
                      "racket/distro-build:debian10"
                      "racket/distro-build:crosslinux-x86_64")
         #:cross-target-machine (and (not on-x86_64?) "ta6le")
         #:cross-target (and (not on-x86_64?) "x86_64-linux-gnu")
         #:configure '("--enable-natipkg")
         (parallel
          (cs-machine
           #:host "natipkg-x86_64"
           #:container-prefix container-prefix
           #:as-default-with-aliases aliases
           (machine
            #:name (make-cs-name linux (linux-x86_64-name #:extra natipkg-name-extra #:order 8))))
          (cs-machine
           #:host "natipkg-x86_64-pkg-build"
           #:container-prefix container-prefix
           (machine
            #:name (make-cs-name linux (linux-x86_64-name #:extra pkg-build-name-extra #:order 9))
            #:compile-any? #t
            #:dist-suffix (string-append debian10-dist-suffix "-pkg-build")))))
        (sequential))
    ;; ----------------------------------------
    ;; Windows
    (parallel
     #:docker "racket/distro-build:crosswin"
     ;; ----------------------------------------
     ;; Windows x86_64
     (parallel
      #:cross-target "x86_64-w64-mingw32"
      #:cross-target-machine "ta6nt"
      #:splice (if windows-sign-post-process
                   (spliceable
                    #:server-installer-post-process windows-sign-post-process)
                   (spliceable))
      #:configure '("CFLAGS=-O2") ; no `-g` to avoid compiler bug when building BC
      (cs+bc-machine
       win-machine
       #:host "crosswin-x86_64"
       #:platform windows
       #:detail win64-name))
     ;; ----------------------------------------
     ;; Windows i386
     (uncommon
      (parallel
       #:cross-target "i686-w64-mingw32"
       #:cross-target-machine "ti3nt"
       (cs+bc-machine
        win-machine
        #:host "crosswin-i386"
        #:platform windows
        #:detail win32-name)))
     ;; ----------------------------------------
     ;; Windows AArch64
     (parallel
      #:cross-target-machine "tarm64nt"
      #:cross-target "aarch64-w64-mingw32"
      #:splice (if windows-sign-post-process
                   (spliceable
                    #:server-installer-post-process windows-sign-post-process)
                   (spliceable))
      (cs+bc-machine
       win-machine
       #:bc? #f ; BC has not been ported to Windows AArch64
       #:host "crosswin-aarch64"
       #:platform windows
       #:detail winarm64-name)))
    ;; ----------------------------------------
    ;; Mac OS
    (parallel
     ;; ----------------------------------------
     ;; Mac OS x86_64
     (parallel
      #:docker "racket/distro-build:osxcross-x86_64"
      #:cross-target-machine "ta6osx"
      #:cross-target "x86_64-apple-darwin13"
      #:configure '("CC=x86_64-apple-darwin13-cc")
      (make-mac-signed
       mac-sign-cert-config
       (make-mac-notarized
        mac-notarization-config
        (cs+bc-machine
         mac-machine
         #:host "osxcross-x86_64"
         #:platform macosx
         #:detail mac-x86_64-name))))
     ;; ----------------------------------------
     ;; Mac OS AArch64
     (parallel
      #:docker "racket/distro-build:osxcross-aarch64"
      #:cross-target-machine "tarm64osx"
      #:cross-target "aarch64-apple-darwin20.2"
      #:configure '("CC=aarch64-apple-darwin20.2-cc")
      (make-mac-signed
       mac-sign-cert-config
       (make-mac-notarized
        mac-notarization-config
        (cs+bc-machine
         mac-machine
         #:host "osxcross-aarch64"
         #:platform macosx
         #:detail mac-aarch64-name))))
     ;; ----------------------------------------
     ;; Mac OS i386
     (uncommon
      (parallel
       #:docker "racket/distro-build:osxcross-i386"
       #:cross-target-machine "ti3osx"
       #:cross-target "i386-apple-darwin10"
       #:configure (append '("CC=i386-apple-darwin10-cc"
                             "--disable-embedfw")
                           (if on-x86_64?
                               ;; `configure` host inference goes wrong for some reason
                               '("--build=x86_64-pc-linux-gnu")
                               null))
       (cs+bc-machine
        mac-machine
        #:host "osxcross-i386"
        #:platform macosx
        #:detail mac-i386-name)))
     ;; ----------------------------------------
     ;; Mac OS PPC
     (uncommon
      (parallel
       #:docker "racket/distro-build:osxcross-ppc"
       #:cross-target-machine "tppc32osx"
       #:cross-target "powerpc-apple-darwin9"
       #:configure '("--disable-embedfw")
       (cs+bc-machine
        mac-machine
        #:host "osxcross-ppc"
        #:platform macosx
        #:detail mac-ppc-name)))))))

(define (make-make-name s vm)
  (case-lambda
   [(platform)
    (~a s " | " platform vm)]
   [(platform detail)
    (~a s " | " platform " | " (if (regexp-match? #rx";" detail)
                                   (regexp-replace #rx";" detail (string-append vm ";"))
                                   (string-append detail vm)))]))

(define (make-site-help)
  (hash "Racket" '(span "The full Racket distribution, including DrRacket"
                        " and a package manager to install more packages.")
        "Minimal Racket" '(span "Includes just enough of Racket that you can use"
                                " " (tt "raco pkg") " to install more.")
        "Minimal DrRacket" '(span "Racket, GUI libraries, DrRacket, and documentation;"
                                  " no teaching languages.")
        "Linux" '(span "If you don't see an option for your particular platform,"
                       " try other Linux installers, starting from"
                       " similar ones. Often, a build for one Linux variant works on"
                       " others, too.")
        (linux-x86_64-name #:extra natipkg-name-extra #:order #f)
        '(span "The " ldquo "natipkg" rdquo
               " distribution uses pre-built and repackaged"
               " versions of system libraries, instead of"
               " relying on the operating system's package"
               " manager to install them.")
        (linux-x86_64-name #:extra pkg-build-name-extra #:order #f)
        '(span "The " ldquo "pkg-build" rdquo
               " distribution is like " ldquo "natipkg" rdquo
               " but also configured to compile collections"
               " and packages to machine-independent form,"
               " which is suitable for the pkg-build service.")
        "Source + built packages" '(span "The core run-time system is provided in source"
                                         " form, but Racket libraries are"
                                         " pre-compiled and documentation"
                                         " is pre-rendered, which enables a quick install.")
        "Source + built libraries" '(span "The core run-time system is provided in source"
                                          " form, but Racket libraries are"
                                          " pre-compiled, which enables a quick install"
                                          " of both Racket and (later) built packages.")
        "Source with versionless path" '(span "The path in the unpacked archive"
                                              " does not include a version number,"
                                              " so it stays the same across versions.")
        "Disk Image" '(span "Drag-and-drop installation, so you get to pick"
                            " the installation path, but you have to set your"
                            " " (tt "PATH") " environment variable.")
        "Installer Package" '(span "Installs and adds Racket executables to the default"
                                   " " (tt "PATH") " (so that command-line tools work),"
                                   " but does not allow a choice of install location.")
        "Tarball" '(span "A " (tt ".tgz") " archive to unpack into any location and run in place.")))

(define (make-site-help-fallbacks)
  (list
   (list #rx"BC" '(span ldquo "BC" rdquo " refers to the old Racket compiler and runtime"
                        " system, which came " (b "B") "efore the one based on"
                        " " (b "C") "hez Scheme."
                        " It's provided for legacy applications and operating systems."))))

(define (make-machines #:minimal? [minimal? #f]
                       #:pkgs [pkgs (if minimal?
                                        '()
                                        '("main-distribution"))]
                       #:installer? [installer? #t]
                       #:tgz? [tgz? minimal?]
                       #:name [distro-name (if minimal?
                                               minimal-racket-name
                                               racket-name)]
                       #:file-name [base (if minimal?
                                             minimal-racket-file-name
                                             racket-file-name)]
                       #:aliases [aliases '()]
                       #:container-prefix [container-prefix "main-dist-"]
                       #:bc? [bc? #f]
                       #:bc-name-suffix [bc-name-suffix " BC"]
                       #:cs? [cs? #t]
                       #:cs-name-suffix [cs-name-suffix ""]
                       #:uncommon? [uncommon? minimal?]
                       #:natipkg? [natipkg? #t]
                       #:extra-linux-variants? [extra-linux-variants? #t]
                       #:windows-sign-post-process [windows-sign-post-process #f]
                       #:mac-sign-cert-config [mac-sign-cert-config #f]
                       #:mac-notarization-config [mac-notarization-config #f]
                       #:recompile-cache [recompile-cache 'main-dist]
                       #:filter-rx [filter-rx #f])
  (when (and minimal? (not (null? pkgs)))
    (error 'make-parallel "package list must be empty for a Minimal Racket configuration"))
  (define (select-format machine/installer+tgz)
    (cond
      [(and installer? tgz?) machine/installer+tgz]
      [installer? machine]
      [tgz? machine/tgz]
      [else machine/none]))
  (filter-machs
   filter-rx
   (make-machs
    container-prefix
    (make-make-name distro-name cs-name-suffix)
    (make-make-name distro-name bc-name-suffix)
    base aliases
    pkgs
    all-platforms
    (if minimal?
        "built libraries"
        "built packages")
    (select-format (make-machine/exe+tgz windows-sign-post-process))
    (select-format machine/dmg+tgz)
    (select-format machine/sh+tgz)
    (if extra-linux-variants?
        (select-format machine/sh+tgz)
        machine/none)
    (if cs?
        cs-machine
        no-machine)
    (if bc?
        bc-machine
        no-machine)
    (if uncommon?
        uncommon
        no-uncommon)
    windows-sign-post-process
    mac-sign-cert-config
    mac-notarization-config
    recompile-cache
    natipkg?)))

(define (make-spliceable-limits #:max-parallel [max-parallel 3]
                                #:timeout [timeout (* #e1.5 60 60)]
                                #:j [j 2])
  (spliceable
   #:max-parallel max-parallel
   #:timeout timeout
   #:j j))

(define (extract-container-names m)
  (define containers
    (let loop ([m m] [host #f] [docker #f] [containers #hash()])
      (cond
        [(site-config? m)
         (define new-host (or (hash-ref (site-config-options m) '#:host #f)
                              host))
         (define new-docker (or (hash-ref (site-config-options m) '#:docker #f)
                                docker))
         (cond
           [(eq? 'machine (site-config-tag m))
            (if new-docker
                (hash-set containers (or host "localhost") #t)
                containers)]
           [else
            (loop (site-config-content m) new-host new-docker containers)])]
        [(null? m) containers]
        [(pair? m)
         (loop (cdr m) host docker (loop (car m) host docker containers))]
        [else containers])))

  (sort (hash-keys containers) string<?))
