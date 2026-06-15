#lang racket/base
(require net/url
         racket/port
         racket/file
         racket/path
         (only-in distro-build/config
                  current-mode
                  site-config?
                  site-config-tag site-config-options site-config-content
                  merge-options
                  current-stamp
                  compose-aliases
                  get-client-name)
         raco/cross
         "private/add-catalog.rkt"
         "private/find-matching.rkt"
         "private/pack-base64.rkt"
         "private/status.rkt"
         "private/log-file-name.rkt"
         "private/merge-catalog.rkt"
         distro-build/installer
         distro-build/readme
         distro-build/display-time
         distro-build/assemble-site)

(provide build-catalog
         merge-catalog
         repackage
         build-docs
         assemble-site)

(define (get-dirs [extra-version #f])
  (define base-dir (path->complete-path (let ([p (build-path "compiled" "repackage")])
                                          (if extra-version
                                              (build-path p extra-version)
                                              p))))
  (define workspace-dir (build-path base-dir "workspace"))
  (define addon-dir (build-path base-dir "addon"))
  (define cache-dir (path->complete-path (build-path "compiled" "download-cache")))
  (values base-dir workspace-dir addon-dir cache-dir))

(define (build-catalog #:version version
                       #:packages packages
                       #:catalogs source-catalogs
                       #:info-catalog [info-catalog "https://pkgs.racket-lang.org"]
                       #:installers-url [installers-url #f]
                       #:original-template [original-template #f]
                       #:default-author [default-author #f]
                       #:dest [dest "build/built"]
                       #:build-deps [build-deps '("draw-lib")]
                       #:config [config-file #f]
                       #:config-mode [config-mode #f])
  (define config
    (and config-file
         (parameterize ([current-mode (or config-mode "default")])
           (dynamic-require (path->complete-path config-file) 'site-config))))

  (define (build-one-catalog #:version [version version]
                             #:as-extra? [as-extra? #f])
    (define-values (base-dir workspace-dir addon-dir cache-dir) (get-dirs (and as-extra? version)))
    (define site-dir (build-path base-dir dest))
    (define cross-identity "catalog-builder")
    (define cross-dir (build-path workspace-dir cross-identity))

    (status "Working in ~a\n" workspace-dir)
    (make-directory* workspace-dir)

    (define (run #:any? [any? #t]
                 #:quiet? [quiet? #f]
                 command
                 . args)
      (apply raco-cross
             #:workspace-dir workspace-dir
             #:compile-any? any?
             #:instance (and any? cross-identity)
             #:quiet? quiet?
             #:addon-dir addon-dir
             #:download-cache-dir cache-dir
             #:skip-pkgs? #true
             #:version version
             #:installers-url installers-url
             #:command command
             args))

    ;; make sure any needed foreign libraries are installed at host
    (apply run #:any? #f
           "pkg" "install" "--auto" "--skip-installed"
           build-deps)

    ;; create machine-indepenent instance
    (run "racket" "-n")

    ;; add new catalogs
    (define orig-catalogs
      (add-catalogs cross-dir source-catalogs))

    ;; install in machine-independent cross target
    (apply run
           "pkg" "install" "-u" "--auto" "--skip-installed"
           packages)
    ;; In case we fixed something after a previous install
    (run "setup")

    (apply run "racket" (collection-file-path "make-catalog.rkt" "distro-build/private")
           (append
            (if original-template
                (list "--original-template" original-template)
                null)
            (if default-author
                (list "--default-author" default-author)
                null)
            (apply append
                   (for/list ([orig-catalog (in-list orig-catalogs)]
                              #:when orig-catalog)
                     (list "++existing-catalog" orig-catalog)))
            (list site-dir
                  info-catalog)
            packages)))

  (build-one-catalog)

  (define extra-versions (remove version
                                 (if config
                                     (hash-ref (merge-options (hasheq) config) '#:repackage-versions '())
                                     '())))
  (unless (null? extra-versions)
    (for ([extra-version (in-list extra-versions)])
      (build-one-catalog #:version extra-version #:as-extra? #t))
    (define-values (base-dir workspace-dir addon-dir cache-dir) (get-dirs))
    (for ([extra-version (in-list extra-versions)])
      (define-values (extra-base-dir extra-workspace-dir extra-addon-dir extra-cache-dir) (get-dirs extra-version))
      (merge-catalog extra-version
                     base-dir
                     extra-base-dir
                     dest))))

(define (repackage #:config config-file
                   #:config-mode [config-mode #f]
                   #:version version
                   #:installers-url [installers-url #f]
                   #:file-name-version [file-name-version version]
                   #:catalogs [catalogs null]
                   #:dist-catalogs [dist-catalogs catalogs]
                   #:version-note [version-note ""]
                   #:skip-notarize? [skip-notarize? #f])
  (define-values (base-dir workspace-dir addon-dir cache-dir) (get-dirs))
  (define readme-file (build-path base-dir "readme.txt"))
  (define log-dir (build-path base-dir "build" "log"))
  (define installers-dir (build-path base-dir "build" "installers"))
  (define installer-table-file (build-path installers-dir "table.rktd"))
  (define cross-identity "repackaged")
  (define cross-dir (build-path workspace-dir cross-identity))

  (define installers-url (string-append "https://mirror.racket-lang.org/installers/" version "/"))

  (define config
    (parameterize ([current-mode (or config-mode "default")])
      (dynamic-require (path->complete-path config-file) 'site-config)))

  (define table-file (build-path base-dir "table.rktd"))
  (unless (file-exists? table-file)
    (make-directory* base-dir)
    (define u (combine-url/relative (string->url installers-url) "table.rktd"))
    (status "Getting table ~a\n" (url->string u))
    (define p (get-pure-port u))
    (call-with-output-file
     table-file
     (lambda (o) (copy-port p o)))
    (close-input-port p))
  (define table (file->value table-file))

  (define (build-one c #:just-plan? [just-plan? #f])
    (define name (hash-ref c '#:name #f))
    (define source? (let ([src? (hash-ref c '#:source? #f)])
                      (hash-ref c '#:source-runtime? src?)))
    (define target (or (hash-ref c '#:cross-target-machine #f)
                       (hash-ref c '#:cross-target #f)
                       (if source?
                           "source"
                           (format "~a-~a"
                                   (system-type 'arch)
                                   (if (and (hash-ref c '#:docker #f)
                                            (not (eq? (system-type) 'unix)))
                                       'linux
                                       (system-type 'os*))))))

    (define key (and name (find-matching name table)))
    (when key
      (status "~a ~a\n  <- ~a\n     ~a\n"
              (if just-plan? "----" "====")
              name
              (or key "SKIP")
              (if source? "source" (format "~a = ~a" target (normalize-platform target)))))

    (define installer-table (if (file-exists? installer-table-file)
                                (file->value installer-table-file)
                                (hash)))
    
    (cond
      [(or just-plan? (not key))
       (void)]
      [(hash-ref installer-table name #f)
       ;; installer already built
       (void)]
      [else
       (make-directory* log-dir)
       (define log-file-name (or (hash-ref c '#:log-file #f)
                                 (simplify-log-file-name name)))
       (status "     ~a\n" log-file-name)
       (define start-time (current-inexact-milliseconds))
       (call-with-output-file*
        (build-path log-dir log-file-name)
        #:exists 'truncate
        (lambda (log-o)
          (file-stream-buffer-mode log-o 'line)
          (parameterize ([current-output-port log-o]
                         [current-error-port log-o])
            (display-time)
            
            (define (run #:quiet? [quiet? #f]
                         command . args)
              (unless quiet?
                (status "raco~a\n"
                        (apply string-append (map (lambda (v) (format " ~a" v))
                                                  (cons command args)))))
              (apply raco-cross
                     #:workspace-dir workspace-dir
                     #:target target
                     #:instance cross-identity
                     #:addon-dir addon-dir
                     #:download-cache-dir cache-dir
                     #:version version
                     #:installers-url installers-url
                     #:quiet? quiet?
                     #:skip-pkgs? #t
                     #:compile-any? source?
                     #:use-source? source?
                     #:archive (hash-ref table key)
                     #:command command
                     args))

            ;; clean up, just in case there's a leftover after a previous error
            (delete-directory/files cross-dir #:must-exist? #f)

            (run "pkg" "config")

            (define orig-cats (add-catalogs cross-dir catalogs))

            (run "pkg" "config")

            (when source?
              ;; disable installation of any platform-specific packages
              (status "Set cross configuration in source\n")
              (define lib-dir (build-path cross-dir "lib"))
              (define sys-file (build-path lib-dir "system.rktd"))
              (make-directory* lib-dir)
              (raco-cross #:workspace-dir workspace-dir
                          #:addon-dir addon-dir
                          #:download-cache-dir cache-dir
                          #:version version
                          #:installers-url installers-url
                          #:command "racket"
                          "-e"
                          (format "~s" `(begin
                                          (require setup/dirs)
                                          (copy-file (build-path (find-lib-dir) "system.rktd")
                                                     ,(path->string sys-file)))))
              (let* ([ht (call-with-input-file* sys-file read)]
                     [ht (hash-set ht 'library-subpath #"source")]
                     #;
                     [ht (hash-set ht 'target-machine #f)])
                (call-with-output-file*
                 sys-file
                 #:exists 'truncate
                 (lambda (o)
                   (writeln ht o)))))

            (apply run "pkg" "install" "-i" "--auto" "--skip-installed" "--recompile-only"
                   (append
                    (if (and source?
                             (hash-ref c '#:source-pkgs? (hash-ref c '#:source? #f)))
                        (list "--source" "--no-setup")
                        null)
                    (hash-ref c '#:pkgs null)))

            (define short-human-name (hash-ref c '#:dist-name "Racket"))
            (define sign-identity (hash-ref c '#:sign-identity ""))
            (define sign-cert-config (hash-ref c '#:sign-cert-config #f))
            (define osslsigncode-args (hash-ref c '#:osslsigncode-args #f))
            (define notarization-config (hash-ref c '#:notarization-config #f))
            (define release? (hash-ref c '#:release? #f))
            (define versionless? (hash-ref c '#:versionless? #f))
            (define install-name (hash-ref c '#:install-name ""))
            (define cross-system-type (or (hash-ref c '#:target-platform #f)
                                          (cond
                                            [(regexp-match? #rx"osx" target) 'macosx]
                                            [(regexp-match? #rx"win32|(nt$)" target) 'windows]
                                            [else 'unix])))
            (define doc-search-url (or (hash-ref c '#:doc-search-url #f)
                                       (let ([v (hash-ref c '#:dist-base-url #f)])
                                         (and v
                                              (url->string
                                               (combine-url/relative (string->url v) "doc/local-redirect/index.html"))))))

            (status "Reset configuration\n")
            (add-catalogs cross-dir dist-catalogs #:keep-old? #f)
            (let ()
              (define config-file (build-path cross-dir "etc" "config.rktd"))
              (let* ([ht (file->value config-file)]
                     [ht (hash-remove ht 'default-scope)]
                     [ht (if (equal? install-name "")
                             (hash-remove ht 'installation-name)
                             (hash-set ht 'installation-name install-name))]
                     [ht (if doc-search-url
                             (hash-set ht 'doc-search-url doc-search-url)
                             ht)])
                (call-with-output-file*
                 config-file
                 #:exists 'truncate
                 (lambda (o) (writeln ht o)))))

            (status "Clean build directory\n")
            (delete-directory/files (build-path cross-dir "build")
                                    #:must-exist? #f)

            (status "Generating README\n")
            (let ([readme (make-readme
                           (hash '#:name name
                                 '#:version version
                                 '#:stamp (string-append "" version-note)
                                 '#:dist-catalogs (append dist-catalogs
                                                          (filter values orig-cats))
                                 '#:versionless? versionless?
                                 '#:install-name install-name
                                 '#:target-platform cross-system-type))])
              (call-with-output-file*
               readme-file
               #:exists 'truncate
               (lambda (o) (display readme o))))
            ;; remove existing README, in case it uses a different extension convention
            (for ([readme (in-list '("README" "README.txt"))])
              (delete-directory/files (build-path cross-dir readme) #:must-exist? #f))

            (when (and source?
                       (hash-ref c '#:source-pkgs? (hash-ref c '#:source? #f)))
              ;; For an original disto build, this step is performed by
              ;; `setup/unixstyle-install post-adjust --source`, but since we
              ;; started with a source distribution, the only thing that needs to
              ;; be fixed up is removing compiled files
              (status "Clean compiled directories\n")
              (for ([p (in-directory (build-path cross-dir "collects")
                                     (lambda (p)
                                       (define-values (base name dir?) (split-path p))
                                       (not (equal? (path->string name) "compiled"))))])
                (define-values (base name dir?) (split-path p))
                (when (equal? (path->string name) "compiled")
                  (delete-directory/files p))))

            (when source?
              ;; remove synthesized "system.rktd"
              (define lib-dir (build-path cross-dir "lib"))
              (delete-directory/files lib-dir))
            
            (parameterize ([current-directory base-dir])
              (delete-directory/files "bundle" #:must-exist? #f)
              (make-directory* "bundle")
              (printf "Packing\n")
              (flush-output)
              (define (maybe-add-version s add? version) (if add? (string-append s "-" version) s))
              (define (config-paths-to-strings ht) (for/hash ([(k v) (in-hash ht)])
                                                     (values k (if (path? v)
                                                                   (path->string v)
                                                                   v))))
              (installer #:short-human-name short-human-name
                         #:human-name (format "~a v~a" short-human-name version)
                         #:base-name (maybe-add-version (hash-ref c '#:dist-base "racket")
                                                        (not versionless?)
                                                        file-name-version)
                         #:dir-name (maybe-add-version (hash-ref c '#:dist-dir "racket")
                                                       (not (or (and release? (not source?))
                                                                versionless?))
                                                       version)
                         #:dist-suffix (let ([s1 (hash-ref c '#:dist-suffix "")]
                                             [s2 (hash-ref c '#:dist-vm-suffix "")])
                                         (define s
                                           (cond
                                             [(equal? s1 "") s2]
                                             [(equal? s2 "") s1]
                                             [else (string-append s1 "-" s2)]))
                                         (if (equal? s "")
                                             ""
                                             (string-append "-" s)))
                         #:sign-identity sign-identity
                         #:osslsigncode-args-base64 (if osslsigncode-args
                                                        (pack-base64-strings osslsigncode-args)
                                                        "")
                         #:sign-cert-base64 (if sign-cert-config
                                                (pack-base64-strings
                                                 (config-paths-to-strings
                                                  sign-cert-config))
                                                "")
                         #:release? release? 
                         #:source? source?
                         #:versionless? versionless?
                         #:tgz? (hash-ref c '#:tgz? #f)
                         #:mac-pkg? (hash-ref c '#:mac-pkg? #f)
                         #:hardened-runtime? (hash-ref c '#:hardened-runtime? (not (equal? sign-identity "")))
                         #:notarization-config (and notarization-config
                                                    (not skip-notarize?)
                                                    (pack-base64-strings
                                                     (config-paths-to-strings notarization-config)))
                         #:download-readme (url->string (path->url readme-file))
                         #:pre-process-cmd (let ([p (hash-ref c '#:client-installer-pre-process '())])
                                             (and (pair? p)
                                                  (pack-base64-strings p)))
                         #:post-process-cmd (let ([p (hash-ref c '#:client-installer-post-process '())])
                                              (and (pair? p)
                                                   (pack-base64-strings p)))
                         #:dist-base-version version
                         #:platform (normalize-platform target)
                         #:cross-system-type cross-system-type
                         #:src-dir cross-dir))

            (define result-name
              (let ([inst (build-path base-dir "bundle" "installer.txt")])
                (and (file-exists? inst)
                     (call-with-input-file inst read-line))))
            (cond
              [result-name
               (printf "Registering result ~a\n" result-name)
               (make-directory* installers-dir)
               (rename-file-or-directory (build-path base-dir result-name)
                                         (build-path installers-dir (file-name-from-path result-name)))
               (call-with-output-file*
                installer-table-file
                #:exists 'truncate
                (lambda (o)
                  (write (hash-set installer-table name (path->string (file-name-from-path result-name))) o)))]
              [else
               (printf "FAILED ~s\n" name)])

            (printf "Removing cross directory\n")
            (delete-directory/files cross-dir)

            (display-time))))
       (status "     ~a\n" (duration->string (- (current-inexact-milliseconds) start-time)))]))

  (define (build just-plan?)
    (let loop ([config config]
               [opts (hasheq)])
      (case (site-config-tag config)
        [(parallel sequential)
         (define new-opts (merge-options opts config))
         (for-each (lambda (c) (loop c new-opts))
                   (site-config-content config))]
        [else
         (define c (merge-options opts config))
         (when (hash-ref c '#:name #f)
           (build-one c #:just-plan? just-plan?))])))

  (build #t)

  ;; make sure needed libraries are available
  (printf "Preparing native\n")
  (raco-cross #:workspace-dir workspace-dir
              #:addon-dir addon-dir
              #:download-cache-dir cache-dir
              #:version version
              #:installers-url installers-url
              #:command "pkg"
              "install" "--auto" "--skip-installed" "draw-lib")

  (build #f))

(define (build-docs #:config config-file
                    #:config-mode [config-mode #f]
                    #:version version
                    #:catalogs [catalogs null]
                    #:installers-url [installers-url #f])
  (define-values (base-dir workspace-dir addon-dir cache-dir) (get-dirs))
  (define readme-file (build-path base-dir "readme.txt"))
  (define log-dir (build-path base-dir "build" "log"))
  (define installers-dir (build-path base-dir "build" "installers"))
  (define installer-table-file (build-path installers-dir "table.rktd"))
  (define doc-cross-identity "doc-maker")
  (define doc-cross-dir (build-path workspace-dir doc-cross-identity))
  (define docs-parent-dir (build-path base-dir "build" "docs"))
  (define doc-dir (build-path docs-parent-dir "doc"))

  (define installers-url (string-append "https://mirror.racket-lang.org/installers/" version "/"))

  (define config
    (parameterize ([current-mode (or config-mode "default")])
      (dynamic-require (path->complete-path config-file) 'site-config)))

  (delete-directory/files doc-cross-dir #:must-exist? #f)

  (define (run command . args)
    (apply raco-cross
           #:workspace-dir workspace-dir
           #:instance doc-cross-identity
           #:addon-dir addon-dir
           #:download-cache-dir cache-dir
           #:version version
           #:installers-url installers-url
           #:skip-pkgs? #t
           #:command command
           args))

  ;; create machine-indepenent instance
  (run "racket" "-n")

  ;; add new catalogs
  (define orig-catalogs
    (add-catalogs doc-cross-dir catalogs))

  (apply run
         "pkg" "install" "--auto"
         (hash-ref (site-config-options config) '#:pkgs null))

  (delete-directory/files doc-dir #:must-exist? #f)
  (make-directory* docs-parent-dir)

  (rename-file-or-directory (build-path doc-cross-dir "doc")
                            doc-dir))
