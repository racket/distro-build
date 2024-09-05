#lang racket/base

(require racket/format
         racket/string
         xml
         (for-syntax syntax/kerncase
                     racket/base))

(provide (except-out (all-from-out racket/base)
                     #%module-begin)
         (rename-out [module-begin #%module-begin])
         sequential
         parallel
         machine
         site-config?
         site-config-tag
         site-config-options
         site-config-content
         current-mode
         current-stamp
         extract-options
         extract-options+post-processes+aliases
         compose-aliases
         infer-installer-alias
         get-client-name
         merge-options)

(module reader syntax/module-reader
  distro-build/config)

(struct site-config (tag options content))

(define-syntax-rule (module-begin form ...)
  (#%plain-module-begin (site-begin #f form ...)))

(define-syntax (site-begin stx)
  (syntax-case stx ()
    [(_ #t) #'(begin)]
    [(_ #f)
     (raise-syntax-error 'site
                         "did not find an expression for the site configuration")]
    [(_ found? next . rest) 
     (let ([expanded (local-expand #'next 'module (kernel-form-identifier-list))])
       (syntax-case expanded (begin)
         [(begin next1 ...)
          #`(site-begin found? next1 ... . rest)]
         [(id . _)
          (and (identifier? #'id)
               (ormap (lambda (kw) (free-identifier=? #'id kw))
                      (syntax->list #'(require
                                       provide
                                       define-values
                                       define-syntaxes
                                       begin-for-syntax
                                       module
                                       module*
                                       #%require
                                       #%provide))))
          #`(begin #,expanded (site-begin found? . rest))]
         [_else
          (if (syntax-e #'found?)
              (raise-syntax-error 'site
                                  "found second top-level expression"
                                  #'next)
              #`(begin
                 (provide site-config)
                 (define site-config (let ([v #,expanded])
                                       (unless (site-config? v)
                                         (error 'site
                                                (~a "expression did not produce a site configuration\n"
                                                    "  result: ~e\n"
                                                    "  expression: ~.s")
                                                v
                                                'next))
                                       v))
                 (site-begin
                  #t
                  . rest)))]))]))

(define sequential
  (make-keyword-procedure
   (lambda (kws kw-vals . subs)
     (constructor kws kw-vals subs
                  check-group-keyword 'sequential))))
(define parallel
  (make-keyword-procedure
   (lambda (kws kw-vals . subs)
     (constructor kws kw-vals subs
                  check-group-keyword 'parallel))))
(define machine
  (make-keyword-procedure
   (lambda (kws kw-vals)
     (constructor kws kw-vals null
                  check-machine-keyword 'machine))))

(define (constructor kws kw-vals subs check tag)
  (site-config
   tag
   (for/hash ([kw (in-list kws)]
              [val (in-list kw-vals)])
     (define r (check kw val))
     (when (eq? r 'bad-keyword)
       (error tag
              (~a "unrecognized keyword for option\n"
                  "  keyword: ~s")
              kw))
     (unless (check kw val)
       (error tag
              (~a "bad value for keyword\n"
                  "  keyword: ~s\n"
                  "  value: ~e")
              kw
              val))
     (values kw val))
   (for/list ([sub subs])
     (unless (site-config? sub)
       (raise-argument-error tag "site-config?" sub))
     sub)))

(define (check-group-keyword kw val)
  (case kw
    [(#:pkgs) (and (list? val) (andmap simple-string? val))]
    [(#:test-pkgs) (and (list? val) (andmap simple-string? val))]
    [(#:test-args) (and (list? val) (andmap string? val))]
    [(#:racket) (or (not val) (string? val))]
    [(#:scheme) (or (not val) (string? val))]
    [(#:cross-target) (or (not val) (simple-string? val))]
    [(#:cross-target-machine) (or (not val) (simple-string? val))]
    [(#:variant) (or (eq? val 'cs) (eq? val 'bc) (eq? val '3m) (eq? val 'cgc))]
    [(#:compile-any?) (boolean? val)]
    [(#:doc-search) (string? val)]
    [(#:dist-name) (string? val)]
    [(#:dist-base) (simple-string? val)]
    [(#:dist-dir) (simple-string? val)]
    [(#:dist-suffix) (simple-string? val)]
    [(#:dist-vm-suffix) (simple-string? val)]
    [(#:dist-aliases) (and (list? val)
                           (andmap (lambda (e)
                                     (and (list? e)
                                          (= (length e) 3)
                                          (andmap (lambda (i)
                                                    (or (not i) (simple-string? i)))
                                                  e)))
                                   val))]
    [(#:dist-catalogs) (and (list? val) (andmap string? val))]
    [(#:dist-base-url) (string? val)]
    [(#:install-name) (string? val)]
    [(#:build-stamp) (string? val)]
    [(#:max-vm) (real? val)]
    [(#:server) (simple-string? val)]
    [(#:server-port) (port-no? val)]
    [(#:server-hosts) (and (list? val) (andmap simple-string? val))]
    [(#:host) (simple-string? val)]
    [(#:user) (or (not val) (simple-string? val))]
    [(#:port) (port-no? val)]
    [(#:dir) (path-string? val)]
    [(#:env) (and (list? val)
                  (andmap (lambda (p)
                            (and (list? p)
                                 (= 2 (length p))
                                 (simple-string? (car p))
                                 (string? (cadr p))))
                          val))]
    [(#:vbox) (string? val)]
    [(#:docker) (string? val)]
    [(#:docker-platform) (or (not val) (string? val))]
    [(#:platform) (memq val '(unix macosx windows windows/bash windows/cmd))]
    [(#:target-platform) (memq val '(unix macosx windows #f))]
    [(#:configure) (and (list? val) (andmap string? val))]
    [(#:bits) (or (equal? val 32) (equal? val 64))]
    [(#:vc) (string? val)]
    [(#:sign-identity) (string? val)]
    [(#:hardened-runtime?) (boolean? val)]
    [(#:osslsigncode-args) (and (list? val) (andmap string? val))]
    [(#:notarization-config) (and (hash? val)
                                  (for/and ([(key val) (in-hash val)])
                                    (case key
                                      [(primary-bundle-id user team) (string? val)]
                                      [(app-specific-password-file) (path-string? val)]
                                      [(wait-seconds) (exact-nonnegative-integer? val)]
                                      [(error-on-fail?) (boolean? val)]
                                      [else #f])))]
    [(#:client-installer-pre-process) (and (list? val) (andmap string? val))]
    [(#:client-installer-post-process) (and (list? val) (andmap string? val))]
    [(#:server-installer-post-process) (and (list? val) (andmap path-string? val))]
    [(#:timeout) (real? val)]
    [(#:make) (string? val)]
    [(#:j) (exact-positive-integer? val)]
    [(#:repo) (string? val)]
    [(#:init) (or (not val) (string? val))]
    [(#:clean?) (boolean? val)]
    [(#:pull?) (boolean? val)]
    [(#:extra-repo-dir) (path-string? val)]
    [(#:release?) (boolean? val)]
    [(#:source?) (boolean? val)]
    [(#:source-runtime?) (boolean? val)]
    [(#:source-pkgs?) (boolean? val)]
    [(#:all-platform-pkgs?) (boolean? val)]
    [(#:static-libs?) (boolean? val)]
    [(#:versionless?) (boolean? val)]
    [(#:dist-base-version) (simple-string? val)]
    [(#:mac-pkg?) (boolean? val)]
    [(#:tgz?) (boolean? val)]
    [(#:fake-installers?) (boolean? val)]
    [(#:site-dest) (path-string? val)]
    [(#:site-help) (and (hash? val)
                        (for/and ([(k v) (in-hash val)])
                          (and (string? k)
                               (xexpr? v))))]
    [(#:site-help-fallbacks) (and (list? val)
                                  (for/and ([k+v (in-list val)])
                                    (and (list? k+v)
                                         (= 2 (length k+v))
                                         (regexp? (car k+v))
                                         (xexpr? (cadr k+v)))))]
    [(#:site-title) (string? val)]
    [(#:current-link-version) (simple-string? val)]
    [(#:pdf-doc?) (boolean? val)]
    [(#:max-snapshots) (real? val)]
    [(#:week-count) (exact-positive-integer? val)]
    [(#:plt-web-style?) (boolean? val)]
    [(#:pause-before) (and (real? val) (not (negative? val)))]
    [(#:pause-after) (and (real? val) (not (negative? val)))]
    [(#:readme) (or (string? val)
                    (and (procedure? val)
                         (procedure-arity-includes? val 1)))]
    [(#:email-to) (and (list? val) (andmap email? val))]
    [(#:email-from) (email? val)]
    [(#:smtp-server) (simple-string? val)]
    [(#:smtp-port) (port-no? val)]
    [(#:smtp-connect) (memq val '(plain ssl tls))]
    [(#:smtp-user) (or (not val) (string? val))]
    [(#:smtp-password) (or (not val) (string? val))]
    [(#:smtp-user+password-file) (or (not val) (path-string? val))]
    [(#:smtp-sending-server) (simple-string? val)]
    [(#:fail-on-client-failures) (boolean? val)]
    [(#:log-file) (string? val)]
    [(#:stream-log?) (boolean? val)]
    [(#:custom) (and (hash? val)
                     (for/and ([k (in-hash-keys val)])
                       (keyword? k)))]
    [else 'bad-keyword]))

(define (check-machine-keyword kw val)
  (case kw
    [(#:name) (string? val)]
    [else (check-group-keyword kw val)]))

(define (port-no? val)
  (and (exact-integer? val) (<= 1 val 65535)))

(define (simple-string? s)
  (and (string? s)
       ;; No spaces, quotes, or other things that could
       ;; break a command-line, path, or URL construction:
       (regexp-match #rx"^[-a-zA-Z0-9._]*$" s)))

(define (email? s)
  (and (string? s)
       (regexp-match? #rx"@" s)))

(define current-mode (make-parameter "default"))

(define current-stamp
  (let* ([f (build-path "build" "stamp.txt")]
         [s (and (file-exists? f)
                 (call-with-input-file* f read-line))])
    (lambda ()
      (if (string? s)
          s
          "now"))))

;; Returns a hash of global options
(define (extract-options config-file config-mode)
  (parameterize ([current-mode config-mode])
    (site-config-options 
     (dynamic-require (path->complete-path config-file) 'site-config))))

;; Returns global options plus a hash mapping names to post-processing
;; executables
(define (extract-options+post-processes+aliases config-file config-mode default-dist-base)
  (parameterize ([current-mode config-mode])
    (define config
      (dynamic-require (path->complete-path config-file) 'site-config))
    (define (traverse at-leaf)
      (let loop ([config config] [pre-opts (hasheq)] [accum (hash)])
        (define opts (merge-options pre-opts config))
        (case (site-config-tag config)
          [(parallel sequential)
           (for/fold ([accum accum]) ([c (in-list (site-config-content config))])
             (loop c opts accum))]
          [else
           (at-leaf opts accum)])))
    (values (site-config-options config)
            (traverse (lambda (opts ht)
                        (define post-process (hash-ref opts '#:server-installer-post-process '()))
                        (if (pair? post-process)
                            (hash-set ht (get-client-name opts) post-process)
                            ht)))
            (traverse (lambda (opts ht)
                        (hash-set ht (get-client-name opts)
                                  (compose-aliases opts default-dist-base)))))))

(define (compose-aliases opts default-dist-base)
  (define main (list (hash-ref opts '#:dist-base default-dist-base)
                     (hash-ref opts '#:dist-suffix "")
                     (hash-ref opts '#:dist-vm-suffix "")))
  (define aliases (for/list ([a (in-list (hash-ref opts '#:dist-aliases '()))])
                    (for/list ([a-i (in-list a)]
                               [m-i (in-list main)])
                      (or a-i m-i))))
  (cons main
        (if (member main aliases)
            aliases
            (append aliases (list main)))))

(define (infer-installer-alias installer main alias
                               #:must-infer? [must-infer? #t])
  ;; Installer is <base>-<version+arch>-<suffix>-<vm-suffix>.<extension>,
  ;; where knowing <base>, <suffix>, and <vm-suffix> from `main` lets us
  ;; infer the rest
  (define base (car main))
  (define suffix (cadr main))
  (define vm-suffix (caddr main))
  (define (combine-suffix suffix vm-suffix)
    (cond
      [(and (equal? suffix "")
            (equal? vm-suffix ""))
       ""]
      [(equal? suffix "") (~a "-" vm-suffix)]
      [(equal? vm-suffix "") (~a "-" suffix)]
      [else (~a "-" suffix "-" vm-suffix)]))
  (define rx (regexp (format "~a-(.*)~a[.]([^.]*)"
                             (regexp-quote base)
                             (regexp-quote (combine-suffix suffix vm-suffix)))))
  (define m (regexp-match rx installer))
  (cond
    [(not m)
     (if must-infer?
         (error 'infer-installer-alias
                "inference failed for ~s from ~s"
                main
                installer)
         #f)]
    [else
     (~a (car alias) "-" (cadr m) (combine-suffix (cadr alias) (caddr alias)) "." (caddr m))]))

(define (get-client-name opts)
  (or (hash-ref opts '#:name #f)
      (hash-ref opts '#:host #f)
      "localhost"))

(define (merge-options opts c)
  (for/fold ([opts opts]) ([(k v) (in-hash (site-config-options c))])
    (if (eq? k '#:custom)
        (hash-set opts
                  '#:custom
                  (let ([prev (hash-ref opts '#:custom (hash))])
                    (for/fold ([prev prev]) ([(k2 v2) (in-hash v)])
                      (hash-set prev k2 v2))))
        (hash-set opts k v))))
