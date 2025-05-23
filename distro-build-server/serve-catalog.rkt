#lang racket/base
(require web-server/servlet-env
         web-server/dispatch
         web-server/http/response-structs
         web-server/http/request-structs
         web-server/safety-limits
         net/url
         racket/format
         racket/cmdline
         racket/file
         racket/path
         racket/string
         racket/tcp
         racket/port
         racket/system
         (only-in distro-build/config extract-options)
         distro-build/readme
         distro-build/record-installer)

(module test racket/base)

(define from-dir "built")

(define-values (config-file config-mode 
                            default-server-hosts default-server-port 
                            during-cmd-line)
  (command-line
   #:once-each
   [("--mode") dir "Serve package archives from <dir> subdirectory"
    (set! from-dir dir)]
   #:args (config-file config-mode server-hosts server-port . during-cmd)
   (values config-file config-mode 
           server-hosts (string->number server-port)
           during-cmd)))

(define server-hosts
  (hash-ref (extract-options config-file config-mode)
            '#:server-hosts
            (string-split default-server-hosts ",")))
(define server-port
  (hash-ref (extract-options config-file config-mode)
            '#:server-port
            default-server-port))
(define extra-repo-dir
  (hash-ref (extract-options config-file config-mode)
            '#:extra-repo-dir
            #f))

(when extra-repo-dir
  (for ([d (in-directory extra-repo-dir)])
    (define-values (base name dir) (split-path d))
    (when (and (path? name)
               (equal? (path->string name) ".git"))
      (printf "Updating ~a\n" base)
      (flush-output)
      (parameterize ([current-directory base])
        (system "git update-server-info")))))

(define build-dir (path->complete-path "build"))
(define built-dir (build-path build-dir from-dir))

(define dirs (list built-dir))

(define (pkg-name->info req name)
  (for/or ([d (in-list dirs)])
    (define f (build-path d "catalog" "pkg" name))
    (and (file-exists? f)
         ;; Change leading "../" to "./" in source, because
         ;; we've shifted "pkg" relative to the site root
         ;; by skipping over "catalog" in the URL.
         (let ([ht (call-with-input-file*
                   f
                   read)])
           (hash-set ht
                     'source
                     (regexp-replace #rx"^[.][.]/"
                                     (hash-ref ht 'source)
                                     "./"))))))

(define (response/sexpr v)
  (response 200 #"Okay" (current-seconds)
            #"text/s-expr" null
            (λ (op) (write v op))))

(define (write-info req pkg-name)
  (response/sexpr (pkg-name->info req pkg-name)))

(define (receive-file req filename)
  (unless (relative-path? filename)
    (error "upload path name must be relative"))
  (define dir (build-path build-dir "installers"))
  (make-directory* dir)
  (call-with-output-file (build-path dir filename)
    #:exists 'truncate/replace
    (lambda (o)
      (write-bytes (request-post-data/raw req) o)))
  (define desc
    (for/or ([h (in-list (request-headers/raw req))])
      (and (equal? (header-field h) #"Description")
           (bytes->string/utf-8 (header-value h)))))
  (record-installer dir filename desc)
  (response/sexpr #t))

(define-values (dispatch main-url)
  (dispatch-rules
   [("pkg" (string-arg)) write-info]
   [("upload" (string-arg)) #:method "put" receive-file]))

;; Tunnel extra hosts to first one:
(when (and (pair? server-hosts)
           (pair? (cdr server-hosts)))
  (for ([host (in-list (cdr server-hosts))])
    (thread
     (lambda ()
       (define l (tcp-listen server-port 5 #t host))
       (define limit (make-semaphore 20)) ; limit concurrency
       (let loop ()
         (semaphore-wait limit)
         (semaphore-wait limit)
         (define-values (i o) (tcp-accept l))
         (with-handlers ([exn:fail:network? (lambda (exn)
                                              (close-input-port i)
                                              (close-output-port o)
                                              (semaphore-post limit)
                                              (semaphore-post limit)
                                              (loop))])
           (define-values (i2 o2) (tcp-connect (car server-hosts) server-port))
           (thread (lambda () 
                     (copy-port i o2)
                     (close-input-port i)
                     (close-output-port o2)
                     (semaphore-post limit)))
           (thread (lambda () 
                     (copy-port i2 o)
                     (close-input-port i2)
                     (close-output-port o)
                     (semaphore-post limit)))
           (loop)))))))

(define (go)
  (serve/servlet
   dispatch
   #:command-line? #t
   #:listen-ip (if (null? server-hosts)
                   #f
                   (car server-hosts))
   #:extra-files-paths
   (append
    (list (build-path build-dir "origin"))
    (list readmes-dir)
    ;; for "pkgs" directories:
    (for/list ([d (in-list dirs)])
      (path->complete-path d))
    ;; for ".git":
    (list (current-directory))
    (if extra-repo-dir
        (list extra-repo-dir)
        null))
   #:servlet-regexp #rx""
   #:safety-limits (make-unlimited-safety-limits)
   #:port server-port))

(define readmes-dir (build-path build-dir "readmes"))
(make-directory* readmes-dir)

(define readme-file (build-path readmes-dir "README.txt"))
(unless (file-exists? readme-file)
  (printf "Generating default README\n")
  (flush-output)
  (call-with-output-file*
   readme-file
   (lambda (o)
     (display (make-readme (hash)) o))))

(if (null? during-cmd-line)
    ;; Just run server:
    (go)
    ;; Run server in a background thread, finish by 
    ;; running given command:
    (let ([t (thread go)])
      (sync (system-idle-evt)) ; try to wait until server is ready
      (unless (apply system*
                     (let ([exe (car during-cmd-line)])
                       (if (and (relative-path? exe)
                                (not (path-only exe)))
                           (find-executable-path exe)
                           exe))
                     (cdr during-cmd-line))
        (error 'server-catalog
               "command failed: ~s" 
               during-cmd-line))))
