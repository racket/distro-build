#lang racket/base
(require racket/cmdline
         racket/system
         racket/port
         racket/format
         racket/file
         racket/string
         racket/path
         net/base64
         (only-in distro-build/config
                  current-mode
                  site-config?
                  site-config-tag site-config-options site-config-content
                  merge-options
                  current-stamp)
         distro-build/url-options
         distro-build/display-time
         distro-build/readme
         remote-shell/vbox
         "email.rkt")

;; See "config.rkt" for an overview.

(module test racket/base)

;; ----------------------------------------

(define default-release? #f)
(define default-source? #f)
(define default-versionless? #f)
(define default-clean? #f)
(define serving-machine-independent? #f)
(define dry-run #f)

(define snapshot-install-name "snapshot")

(define-values (config-file config-mode
                            default-server default-server-port default-server-hosts
                            default-pkgs default-doc-search
                            default-dist-name default-dist-base default-dist-dir)
  (command-line
   #:once-each
   [("--release") "Create release-mode installers"
    (set! default-release? #t)]
   [("--source") "Create source installers"
    (set! default-source? #t)]
   [("--versionless") "Avoid version number in names and paths"
    (set! default-versionless? #t)]
   [("-M" "--compile-any") "Serving machine-independent bytecode"
    (set! serving-machine-independent? #t)]
   [("--clean") "Erase client directories before building"
    (set! default-clean? #t)]
   [("--dry-run") mode
    ("Don't actually use the clients;"
     " <mode> can be `ok`, `fail`, `error`, `stuck`, or `frozen`")
    (unless (member mode '("ok" "fail" "error" "stuck" "frozen"))
      (raise-user-error 'drive-clients "bad dry-run mode: ~a" mode))
    (set! dry-run (string->symbol mode))]
   [("--describe") "Similar to `--dry-run`, but shows more details"
    (set! dry-run 'describe)]
   #:args (config-file config-mode 
                       server server-port server-hosts pkgs doc-search
                       dist-name dist-base dist-dir)
   (values config-file config-mode
           server server-port server-hosts pkgs doc-search
           dist-name dist-base dist-dir)))

(define config (parameterize ([current-mode config-mode])
                 (dynamic-require (path->complete-path config-file) 'site-config)))

(unless (site-config? config)
  (error 'drive-clients 
         "configuration module did not provide a site-configuration value: ~e"
         config))

;; ----------------------------------------

(define (get-opt opts kw [default #f] #:localhost [localhost-default default])
  (hash-ref opts kw (lambda ()
                      (cond
                       [(equal? default localhost-default) default]
                       [(and (equal? "localhost" (get-opt opts '#:host "localhost"))
                             (equal? #f (get-opt opts '#:user #f))
                             (equal? #f (get-opt opts '#:dir #f)))
                        localhost-default]
                       [else default]))))

(define (get-content c)
  (site-config-content c))

(define (client-log-file opts)
  (or (get-opt opts '#:log-file)
      (client-name opts)))

(define (client-name opts)
  (or (get-opt opts '#:name)
      (get-opt opts '#:host)
      "localhost"))

(define (client-stream-log? opts)
  (get-opt opts '#:stream-log?))

(define (get-path-opt opt key default #:localhost [localhost-default default])
  (define d (get-opt opt key default #:localhost localhost-default))
  (if (path? d)
      (path->string d)
      d))

(define (add-defaults c . l)
  (let loop ([c c] [l l])
    (cond
     [(null? l) c]
     [else (loop (hash-set c (car l) 
                           (hash-ref c (car l) (lambda () (cadr l))))
                 (cddr l))])))

;; ----------------------------------------
;; Managing VirtualBox machines

(define (start-client c max-vm)
  (define vbox (get-opt c '#:vbox))
  (when vbox
    (start-vbox-vm vbox
                   #:max-vms max-vm
                   #:dry-run? dry-run)))

(define (stop-client c)
  (define vbox (get-opt c '#:vbox))
  (when vbox
    (stop-vbox-vm vbox)))

(define (try-until-ready c host port user server-port kind cmd)
  (when (get-opt c '#:vbox)
    ;; A VM may take a little while to get networking set up and
    ;; respond, so give a dummy `cmd` a few tries
    (let loop ([tries 3])
      (unless (ssh-script host port user server-port kind cmd)
        (sleep 1)
        (loop (sub1 tries))))))

;; ----------------------------------------

(define describe-indent (make-parameter ""))
(define (next-describe-indent)
  (string-append (describe-indent) "   "))

(define (describe desc)
  (when (eq? dry-run 'describe)
    (printf "~a---- ~a ----\n"
            (describe-indent)
            desc)))

(define describe-both-keys
  '(#:pkgs
    #:test-pkgs
    #:test-args))

(define describe-top-keys
  '(#:doc-search
    #:dist-base-url
    #:server-hosts
    #:extra-repo-dir
    #:site-dest
    #:site-help
    #:site-title
    #:pdf-doc?
    #:max-snapshots
    #:week-count
    #:plt-web-style?
    #:email-to
    #:email-from
    #:smtp-server
    #:smtp-port
    #:smtp-connect
    #:smtp-user
    #:smtp-password
    #:fail-on-client-failures
    #:custom))

(define describe-never-keys
  '(#:name))

(define (describe-config c #:show-top? [show-top? #f])
  (when (eq? dry-run 'describe)
    (for ([k (in-list (sort (hash-keys c) keyword<?))])
      (define top? (and (memq k describe-top-keys) #t))
      (when (and (or (eq? top? show-top?)
                     (memq k describe-both-keys))
                 (not (memq k describe-never-keys)))
        (printf "~a~a: ~v\n"
                (describe-indent)
                (keyword->string k)
                (hash-ref c k))))))

(define (displayln/wrap-for-describe s)
  (cond
    [(eq? dry-run 'describe)
     (define w (max 20 (- 72 (string-length (describe-indent)))))
     (cond
       [((string-length s) . <= . w)
        (display (describe-indent))
        (displayln s)]
       [else
        (let loop ([i w])
          (cond
            [(zero? i)
             (let loop ([i w])
               (cond
                 [(= i (string-length s))
                  (display (describe-indent))
                  (displayln s)]
                 [(eqv? #\space (string-ref s i))
                  (displayln/wrap-for-describe (substring s 0 i))
                  (displayln/wrap-for-describe (substring s i))]
                 [else (loop (add1 i))]))]
            [(eqv? #\space (string-ref s i))
             (displayln/wrap-for-describe (substring s 0 i))
             (displayln/wrap-for-describe (substring s i))]
            [else (loop (sub1 i))]))])]
    [else
     (displayln s)]))

;; ----------------------------------------

(define scp (find-executable-path "scp"))
(define ssh (find-executable-path "ssh"))

(define (system*/show exe . args)
  (displayln/wrap-for-describe
   (apply ~a #:separator " "
          (append
           (if (eq? dry-run 'describe) '("exec:") '())
           (map (lambda (p) (if (path? p) (path->string p) p)) 
                (cons exe args)))))
  (flush-output)
  (case dry-run
    [(ok describe) #t]
    [(fail) #f]
    [(error) (error "error")]
    [(stuck) (semaphore-wait (make-semaphore))]
    [(frozen) (break-enabled #f) (semaphore-wait (make-semaphore))]
    [else
     (apply system* exe args)]))

(define (ssh-script host port user server-port kind . cmds)
  (for/and ([cmd (in-list cmds)])
    (when cmd
      (unless (eq? dry-run 'describe)
        (display-time #:server? #t)))
    (or (not cmd)
        (if (and (equal? host "localhost")
                 (not user))
            ;; Run client locally:
            (parameterize ([current-environment-variables
                            (environment-variables-copy (current-environment-variables))])
              ;; Prevent any makefile variables from the server setup
              ;; from being propagated to the client build:
              (environment-variables-set! (current-environment-variables) #"MAKEFLAGS" #f)
              ;; Run client in a shell:
              (apply system*/show cmd))
            ;; Run client remotely:
            (apply system*/show ssh 
                   "-p" (~a port)
                   ;; create tunnel to connect back to server:
                   "-R" (~a server-port ":localhost:" server-port)
                   (if user 
                       (~a user "@" host)
                       host)
                   (if (eq? kind 'unix)
                       ;; ssh needs an extra level of quoting
                       ;;  relative to sh:
                       (for/list ([arg (in-list cmd)])
                         (~a "'" 
                             (regexp-replace* #rx"'" arg "'\"'\"'")
                             "'"))
                       ;; windows quoting built into `cmd' aready
                       cmd))))))

(define (q s)
  (~a "\"" s "\""))

(define (qq l kind)
  (case kind
    [(unix macosx)
     (~a "'"
         (apply ~a #:separator " " (map q l))
         "'")]
    [(windows windows/bash windows/cmd)
     (~a "\""
         (apply 
          ~a #:separator " " 
          (for/list ([i (in-list l)])
            (~a "\\\""
                i
                ;; A backslash is literal unless followed by a
                ;; quote. If `i' ends in backslashes, they
                ;; must be doubled, because the \" added to
                ;; the end will make them treated as escapes.
                (let ([m (regexp-match #rx"\\\\*$" i)])
                  (car m))
                "\\\"")))
         "\"")]))

(define (shell-protect s kind)
  (case kind
    [(windows/bash)
     ;; Protect Windows arguments to go through bash, where
     ;; unquoted backslashes must be escaped, but quotes are effectively
     ;; preserved by the shell, and quoted backslashes should be left
     ;; alone; also, "&&" must be quoted to avoid parsing by bash
     (regexp-replace* "&&"
                      (list->string
                       ;; In practice, the following loop is likely to
                       ;; do nothing, because constructed command lines
                       ;; tend to have only quoted backslashes.
                       (let loop ([l (string->list s)] [in-quote? #f])
                         (cond
                          [(null? l) null]
                          [(and (equal? #\\ (car l))
                                (not in-quote?))
                           (list* #\\ #\\ (loop (cdr l) #f))]
                          [(and in-quote?
                                (equal? #\\ (car l))
                                (pair? (cdr l))
                                (or (equal? #\" (cadr l))
                                    (equal? #\\ (cadr l))))
                           (list* #\\ (cadr l) (loop (cddr l) #t))]
                          [(equal? #\" (car l))
                           (cons #\" (loop (cdr l) (not in-quote?)))]
                          [else
                           (cons (car l) (loop (cdr l) in-quote?))])))
                      "\"\\&\\&\"")]
    [else s]))

(define (pack-base64-strings args)
  (bytes->string/utf-8 (base64-encode (string->bytes/utf-8 (format "~s" args))
                                      #"")))

(define (client-args c server server-port kind readme)
  (define desc (client-name c))
  (define pkgs (let ([l (get-opt c '#:pkgs)])
                 (if l
                     (apply ~a #:separator " " l)
                     default-pkgs)))
  (define racket (get-opt c '#:racket))
  (define variant (or (get-opt c '#:variant) '3m))
  (define cs? (eq? variant 'cs))
  (define scheme (and cs?
                      (get-opt c '#:scheme)))
  (define extra-repos? (and (get-opt c '#:extra-repo-dir) #t))
  (define doc-search (choose-doc-search c default-doc-search))
  (define dist-name (or (get-opt c '#:dist-name)
                        default-dist-name))
  (define dist-base (or (get-opt c '#:dist-base)
                        default-dist-base))
  (define dist-dir (or (get-opt c '#:dist-dir)
                       default-dist-dir))
  (define dist-suffix (get-opt c '#:dist-suffix ""))
  (define dist-catalogs (choose-catalogs c '("")))
  (define sign-identity (get-opt c '#:sign-identity ""))
  (define hardened-runtime? (get-opt c '#:hardened-runtime? (not (equal? sign-identity ""))))
  (define installer-pre-process (get-opt c '#:client-installer-pre-process '()))
  (define installer-post-process (get-opt c '#:client-installer-post-process '()))
  (define osslsigncode-args (get-opt c '#:osslsigncode-args))
  (define release? (get-opt c '#:release? default-release?))
  (define source? (get-opt c '#:source? default-source?))
  (define versionless? (get-opt c '#:versionless? default-versionless?))
  (define source-pkgs? (get-opt c '#:source-pkgs? source?))
  (define source-runtime? (get-opt c '#:source-runtime? source?))
  (define all-platform-pkgs? (get-opt c '#:all-platform-pkgs?))
  (define static-libs? (get-opt c '#:static-libs? #f))
  (define mac-pkg? (get-opt c '#:mac-pkg? #f))
  (define tgz? (get-opt c '#:tgz? #f))
  (define install-name (get-opt c '#:install-name (if release? 
                                                      "" 
                                                      snapshot-install-name)))
  (define build-stamp (get-opt c '#:build-stamp (if release?
                                                    ""
                                                    (current-stamp))))
  (~a " SERVER=" server
      " SERVER_PORT=" server-port
      " PKGS=" (q pkgs)
      (if racket
          (~a " PLAIN_RACKET=" (q racket))
          "")
      (if (and racket cs?)
          (~a " RACKET=" (q racket))
          "")
      (if scheme
          (~a " SCHEME_SRC=" (q scheme))
          "")
      (if extra-repos?
          (~a " EXTRA_REPOS_BASE=http://" server ":" server-port "/")
          "")
      " DOC_SEARCH=" (q doc-search)
      " DIST_DESC=" (q desc)
      " DIST_NAME=" (q dist-name)
      " DIST_BASE=" dist-base
      " DIST_DIR=" dist-dir
      " DIST_SUFFIX=" (q dist-suffix)
      " DIST_CATALOGS_q=" (qq dist-catalogs kind)
      " SIGN_IDENTITY=" (q sign-identity)
      " INSTALLER_OPTIONS=\"" (if hardened-runtime? "hardened," "") "\""
      " OSSLSIGNCODE_ARGS_BASE64=" (q (if osslsigncode-args
                                          (pack-base64-strings osslsigncode-args)
                                          ""))
      (if (pair? installer-pre-process)
          (~a " INSTALLER_PRE_PROCESS_BASE64=" (q (pack-base64-strings installer-pre-process)))
          "")
      (if (pair? installer-post-process)
          (~a " INSTALLER_POST_PROCESS_BASE64=" (q (pack-base64-strings installer-post-process)))
          "")
      " INSTALL_NAME=" (q install-name)
      " BUILD_STAMP=" (q build-stamp)
      " RELEASE_MODE=" (if release? "--release" (q ""))
      " SOURCE_MODE=" (if source-runtime? "--source" (q ""))
      " VERSIONLESS_MODE=" (if versionless? "--versionless" (q ""))
      " PKG_SOURCE_MODE=" (if source-pkgs?
                              (q "--source --no-setup")
                              (q ""))
      " DISABLE_STATIC_LIBS=" (if static-libs?
                                  (q "")
                                  (q "--disable-libs"))
      (if all-platform-pkgs?
          " PKG_INSTALL_OPTIONS=--all-platforms"
          "")
      " UNPACK_COLLECTS_FLAGS=" (if (and cs?
                                         (not serving-machine-independent?))
                                    "--skip"
                                    "")
      " MAC_PKG_MODE=" (if mac-pkg? "--mac-pkg" (q ""))
      " TGZ_MODE=" (if tgz? "--tgz" (q ""))
      " UPLOAD=http://" server ":" server-port "/upload/"
      " README=http://" server ":" server-port "/" (q (file-name-from-path readme))
      " TEST_PKGS=" (q (apply ~a #:separator " " (get-opt c '#:test-pkgs '())))
      " TEST_ARGS_q=" (qq (get-opt c '#:test-args '()) kind)))

(define (has-tests? c)
  (and (pair? (get-opt c '#:test-args '()))
       (not (get-opt c '#:source-runtime? (get-opt c '#:source? default-source?)))
       (not (or (get-opt c '#:cross-target)
                (get-opt c '#:cross-target-machine)))))

(define (infer-machine target)
  (case target
    [("x86_64-w64-mingw32") "ta6nt"]
    [("i686-w64-mingw32") "ti3nt"]
    [else #f]))

(define (unix-build c platform host port user server server-port repo init clean? pull? readme)
  (define dir (get-path-opt c '#:dir "build/plt" #:localhost (current-directory)))
  (define env (get-opt c '#:env null))
  (define (sh . args)
    (append
     (if (null? env)
         null
         (list* "/usr/bin/env"
                (for/list ([e (in-list env)])
                  (format "~a=~a" (car e) (cadr e)))))
     (list "/bin/sh" "-c" (apply ~a args))))
  (define j (or (get-opt c '#:j) 1))
  (define variant (or (get-opt c '#:variant) '3m))
  (define cs? (eq? variant 'cs))
  (define compile-any? (get-opt c '#:compile-any?))
  (define cross-target (get-opt c '#:cross-target))
  (define cross-target-machine (and cs?
                                    (or (get-opt c '#:cross-target-machine)
                                        (and cross-target
                                             (infer-machine cross-target)))))
  (define cross? (or cross-target cross-target-machine))
  (define given-racket (and cross?
                            (get-opt c '#:racket)))
  (define scheme (and cs?
                      (get-opt c '#:scheme)))
  (define need-native-racket? (and cross?
                                   (not given-racket)))
  (define built-native-racket
    ;; relative to build directory
    (if cs? "cross/cs/c/racketcs" "cross/racket/racket3m"))
  (define extra-repos? (and (get-opt c '#:extra-repo-dir) #t))
  (try-until-ready c host port user server-port 'unix (sh "echo hello"))
  (ssh-script
   host port user
   server-port
   'unix
   (and init
        (sh init))
   (and clean?
        (sh "rm -rf  " (q dir)))
   (sh "if [ ! -d " (q dir) " ] ; then"
       " git clone " (q repo) " " (q dir) " ; "
       "fi")
   (and pull?
        (sh "cd " (q dir) " ; "
            "git pull"))
   (and need-native-racket?
        (sh "cd " (q dir) " ; "
            "make -j " j " native-" (if cs? "cs-" "") "for-cross"
            (if scheme
                (~a " SCHEME_SRC=" (q scheme))
                "")
            (if (and cs? extra-repos?)
                (~a " EXTRA_REPOS_BASE=http://" server ":" server-port "/")
                "")))
   (sh "cd " (q dir) " ; "
       "make -j " j " client" (if compile-any? "-compile-any" "")
       (client-args c server server-port 'unix readme)
       " JOB_OPTIONS=\"-j " j "\""
       (if need-native-racket?
           (~a " PLAIN_RACKET=`pwd`/racket/src/build/" built-native-racket
               (if cs?
                   (~a " RACKET=`pwd`/racket/src/build/" built-native-racket
                       (if scheme
                           ""
                           " SCHEME_SRC=`pwd`/racket/src/build/cross/ChezScheme"))
                   ""))
           "")
       (if cs?
           " CLIENT_BASE=cs-base RACKETCS_SUFFIX= "
           "")
       (if cross?
           " BUNDLE_FROM_SERVER_TARGET=bundle-cross-from-server"
           "")
       (if (and cross? cs?)
           " CS_CROSS_SUFFIX=-cross"
           "")
       (if cross-target-machine
           (~a " SETUP_MACHINE_FLAGS=\"--cross-compiler " cross-target-machine
               " `pwd`/racket/src/build/cs/c/ -MCR `pwd`/build/zo:\"")
           "")
       " CONFIGURE_ARGS_qq=" (qq (append
                                  (if cross-target
                                      (list (~a "--host=" cross-target))
                                      null)
                                  (if cross?
                                      (list (~a "--enable-racket="
                                                (or given-racket
                                                    (~a "`pwd`/" built-native-racket))))
                                      null)
                                  (if (and cs? scheme)
                                      (list (~a "--enable-scheme=" scheme))
                                      null)
                                  (list "--enable-embedfw")
                                  (get-opt c '#:configure null))
                                 'unix))
   (and (has-tests? c)
        (sh "cd " (q dir) " ; "
            "make test-client"
            (client-args c server server-port 'unix readme)
            (if need-native-racket?
                (~a " PLAIN_RACKET=`pwd`/racket/src/build/" built-native-racket)
                "")))))

(define (windows-build c platform host port user server server-port repo init clean? pull? readme)
  (define dir (get-path-opt c '#:dir "build\\plt" #:localhost (current-directory)))
  (define bits (or (get-opt c '#:bits) 64))
  (define vc (or (get-opt c '#:vc)
                 (if (= bits 32)
                     "x86"
                     "x86_amd64")))
  (define j (or (get-opt c '#:j) 1))
  (define variant (or (get-opt c '#:variant) '3m))
  (define (cmd . args) 
    (define command (shell-protect (apply ~a args) platform))
    (case platform
      [(windows/cmd) (list command)]
      [else (list "cmd" "/c" command)]))
  (try-until-ready c host port user server-port 'windows (cmd "echo hello"))
  (ssh-script
   host port user
   server-port
   platform
   (and init
        (cmd init))
   (and clean?
        (cmd "IF EXIST " (q dir) " rmdir /S /Q " (q dir)))
   (cmd "IF NOT EXIST " (q dir) " git clone " (q repo) " " (q dir))
   (and pull?
        (cmd "cd " (q dir)
             " && git pull"))
   (cmd "cd " (q dir)
        " && racket\\src\\worksp\\msvcprep.bat " vc
        " && nmake win32-client" 
        " JOB_OPTIONS=\"-j " j "\""
        (if (eq? variant 'cs)
            " WIN32_CLIENT_BASE=win32-cs-base RACKETCS_SUFFIX= "
            "")
        (client-args c server server-port platform readme))
   (and (has-tests? c)
        (cmd "cd " (q dir)
             " && racket\\src\\worksp\\msvcprep.bat " vc
             " && nmake win32-test-client"
             (client-args c server server-port platform readme)))))

(define (client-build c)
  (describe (client-name c))
  (describe-config c)
  (define host (or (get-opt c '#:host)
                   "localhost"))
  (define port (or (get-opt c '#:port)
                   22))
  (define user (get-opt c '#:user))
  (define server (or (get-opt c '#:server)
                     default-server))
  (define server-port (or (get-opt c '#:server-port)
                          default-server-port))
  (define repo (or (get-opt c '#:repo)
                   (~a "http://" server ":" server-port "/.git")))
  (define init (get-opt c '#:init))
  (define clean? (get-opt c '#:clean? default-clean? #:localhost #f))
  (define pull? (get-opt c '#:pull? #t #:localhost #f))

  (define readme-txt (let ([rdme (get-opt c '#:readme make-readme)])
                       (if (string? rdme)
                           rdme
                           (rdme (add-defaults c
                                               '#:release? default-release?
                                               '#:source? default-source?
                                               '#:versionless? default-versionless?
                                               '#:pkgs (string-split default-pkgs)
                                               '#:install-name (if (get-opt c '#:release? default-release?)
                                                                   ""
                                                                   snapshot-install-name)
                                               '#:build-stamp (if (get-opt c '#:release? default-release?)
                                                                  ""
                                                                  (current-stamp)))))))
  (define readme
    (cond
      [(eq? dry-run 'describe)
       "readme"]
      [else
       (make-directory* (build-path "build" "readmes"))
       (define readme (make-temporary-file
                       "README-~a"
                       #f
                       (build-path "build" "readmes")))
       (call-with-output-file*
        readme
        #:exists 'truncate
        (lambda (o)
          (display readme-txt o)
          (unless (regexp-match #rx"\n$" readme-txt)
            ;; ensure a newline at the end:
            (newline o))))
       readme]))

  (define platform (or (get-opt c '#:platform) (system-type)))

  (begin0

   ((case platform
      [(unix macosx) unix-build]
      [else windows-build])
    c platform host port user server server-port repo init clean? pull? readme)

   (unless (eq? dry-run 'describe)
     (delete-file readme))))

;; ----------------------------------------

(define stop? #f)

(define failures (make-hasheq))
(define (record-failure name)
  ;; relies on atomicity of `eq?'-based hash table:
  (hash-set! failures (string->symbol name) #t))

(define (limit-and-report-failure c timeout-factor
                                  shutdown report-fail
                                  thunk)
  (define cust (make-custodian))
  (define timeout (or (get-opt c '#:timeout)
                      (* 30 60)))
  (define orig-thread (current-thread))
  (define timeout? #f)
  (begin0
   (parameterize ([current-custodian cust])
     (thread (lambda ()
               (sleep (* timeout-factor timeout))
               (eprintf "timeout for ~s\n" (client-name c))
               ;; try nice interrupt, first:
               (set! timeout? #t)
               (break-thread orig-thread)
               (sleep 1)
               ;; force quit:
               (report-fail)
               (shutdown)))
     (with-handlers ([exn? (lambda (exn)
                             (when (exn:break? exn)
                               ;; This is useful only when everything is
                               ;; sequential, which is the only time that
                               ;; we'll get break events that aren't timeouts:
                               (unless timeout?
                                 (set! stop? #t)))
                             (log-error "~a failed..." (client-name c))
                             (log-error (exn-message exn))
                             (report-fail)
                             #f)])
       (thunk)))
   (custodian-shutdown-all cust)))


(define (tee . p*)
  (let-values ([(inp outp) (make-pipe)])
    (thread
     (lambda ()
       (apply copy-port inp p*)))
    outp))

(define (client-thread c all-seq? proc)
  (unless stop?
    (define log-dir (build-path "build" "log"))
    (define log-file (build-path log-dir (client-log-file c)))
    (make-directory* log-dir)
    (printf "Logging build: ~a\n" log-file)
    (flush-output)
    (define cust (make-custodian))
    (define (go shutdown)
      (define p (open-output-file log-file
                                  #:exists 'truncate/replace))
      (define err-p (if (client-stream-log? c) (tee p (current-error-port)) p))
      (define out-p (if (client-stream-log? c) (tee p (current-output-port)) p))
      (file-stream-buffer-mode p 'line)
      (define (report-fail)
        (record-failure (client-name c))
        (printf "Build FAILED for ~s\n" (client-name c)))
      (define start-milliseconds (current-inexact-milliseconds))
      (unless (parameterize ([current-output-port err-p]
                             [current-error-port out-p])
                (proc shutdown report-fail))
        (report-fail))
      (printf "Duration for ~a: ~a\n"
              (client-name c)
              (duration->string (- (current-inexact-milliseconds)
                                   start-milliseconds)))
      (flush-output)
      (display-time #:server? #t))
    (cond
     [all-seq? 
      (go (lambda () (exit 1)))
      (thread void)]
     [else
      (parameterize ([current-custodian cust])
        (thread
         (lambda ()
           (go (lambda ()
                 (custodian-shutdown-all cust))))))])))

;; ----------------------------------------

(define start-seconds (current-seconds))
(unless (eq? dry-run 'describe)
  (display-time #:server? #t))

(define (build-thread thunk)
  (if (eq? dry-run 'describe)
      (begin
        (thunk) ; run thunk sequentially
        (thread void))
      (thread thunk)))

(when (eq? dry-run 'describe)
  (describe "Top")
  (describe-config (merge-options #hasheq() config) #:show-top? #t))

(void
 (sync
  (let loop ([config config]
             [all-seq? #t] ; Ctl-C handling is better if nothing is in parallel
             [in-seq? #t]  ; prettier describe
             [opts (hasheq)])
    (cond
     [stop? (build-thread void)]
     [else
      (case (site-config-tag config)
        [(parallel)
         (describe "PARALLEL")
         (define new-opts (merge-options opts config))
         (define ts
           (parameterize ([describe-indent (next-describe-indent)])
             (map (lambda (c) (loop c #f #f new-opts))
                  (get-content config))))
         (build-thread
          (lambda ()
            (for ([t (in-list ts)])
              (sync t))))]
        [(sequential)
         (define content (get-content config))
         (define nest? (not (or in-seq? ((length content) . <= . 1))))
         (define now-in-seq? (or in-seq? nest?))
         (when nest? (describe "SEQUENTIAL"))
         (define new-opts (merge-options opts config))
         (define (go)
           (for-each (lambda (c) (sync (loop c all-seq? now-in-seq? new-opts)))
                     content))
         (parameterize ([describe-indent (if nest?
                                             (next-describe-indent)
                                             (describe-indent))])
           (if all-seq?
               (begin (go) (build-thread void))
               (build-thread go)))]
        [else
         (define c (merge-options opts config))
         (cond
           [(eq? dry-run 'describe)
            ;; Don't need error handling, etc.:
            (build-thread
             (lambda () (client-build c)))]
           [else
            (client-thread
             c
             all-seq?
             (lambda (shutdown report-fail)
               (limit-and-report-failure
                c 2 shutdown report-fail
                (lambda ()
                  (sleep (get-opt c '#:pause-before 0))
                  ;; start client, if a VM:
                  (start-client c (or (get-opt c '#:max-vm) 1))
                  ;; catch failure in build step proper, so we
                  ;; can more likely stop the client:
                  (begin0
                    (limit-and-report-failure
                     c 1 shutdown report-fail
                     (lambda () (client-build c)))
                    ;; stop client, if a VM:
                    (stop-client c)
                    (sleep (get-opt c '#:pause-after 0)))))))])])]))))

(unless (eq? dry-run 'describe)
  (display-time #:server? #t)
  (define end-seconds (current-seconds))

  (let ([opts (merge-options (hasheq) config)])
    (unless stop?
      (let ([to-email (get-opt opts '#:email-to null)])
        (unless (null? to-email)
          (printf "Sending report to ~a\n" (apply ~a to-email #:separator ", "))
          (send-email to-email (lambda (key def)
                                 (get-opt opts key def))
                      (get-opt opts '#:build-stamp (current-stamp))
                      start-seconds end-seconds
                      (hash-map failures (lambda (k v) (symbol->string k))))
          (display-time #:server? #t))))
    (when (get-opt opts '#:fail-on-client-failures)
      ;; exit with non-0 return code in case of any client failure
      (unless (hash-empty? failures)
        (exit 1)))))
