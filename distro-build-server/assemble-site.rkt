#lang racket/base
(require racket/cmdline
         racket/file
         racket/system
         net/url
         "download-page.rkt"
         "indexes.rkt"
         (only-in distro-build/config
                  extract-options+post-processes+aliases
                  infer-installer-alias)
         (only-in plt-web site)
         (only-in xml write-xexpr))

(module test racket/base)

(define build-dir (build-path "build"))

(define built-dir (build-path build-dir "built"))
(define native-dir (build-path build-dir "native"))
(define docs-dir (build-path build-dir "docs"))

(define installers-dir (build-path "installers"))
(define pkgs-dir (build-path "pkgs"))
(define catalog-dir (build-path "catalog"))
(define from-catalog-dir-to-pkgs-dir (build-path 'up))
(define doc-dir (build-path "doc"))
(define pdf-doc-dir (build-path "pdf-doc"))
(define log-dir (build-path "log"))

(define-values (config-file config-mode default-dist-base)
  (command-line
   #:args
   (config-file config-mode default-dist-base)
   (values config-file config-mode default-dist-base)))

(define-values (config post-processes aliases)
  (extract-options+post-processes+aliases config-file config-mode default-dist-base))

(define dest-dir (hash-ref config
                           '#:site-dest
                           (build-path build-dir "site")))

(define site-title (hash-ref config
                             '#:site-title
                             "Racket Downloads"))

(define www-site (and (hash-ref config '#:plt-web-style? #t)
                      (site "www"
                            #:url "https://racket-lang.org/"
                            #:generate? #f)))

(printf "Assembling site as ~a\n" dest-dir)

(define (copy dir [build-dir build-dir])
  (make-directory* (let-values ([(base name dir?) (split-path dir)])
                     (if (path? base)
                         (build-path dest-dir base)
                         dest-dir)))
  (printf "Copying ~a\n" (build-path build-dir dir))
  (copy-directory/files (build-path build-dir dir)
                        (build-path dest-dir dir)
                        #:keep-modify-seconds? #t))

(delete-directory/files dest-dir #:must-exist? #f)

(define (build-catalog built-dir)
  (printf "Building catalog from ~a\n" built-dir)
  (let ([c-dir (build-path built-dir pkgs-dir)]
        [d-dir (build-path dest-dir pkgs-dir)])
    (make-directory* d-dir)
    (for ([f (directory-list c-dir)])
      (define c (build-path c-dir f))
      (define d (build-path d-dir f))
      (copy-file c d)
      (file-or-directory-modify-seconds d (file-or-directory-modify-seconds c))))
  (let ([c-dir (build-path built-dir catalog-dir "pkg")]
        [d-dir (build-path dest-dir catalog-dir "pkg")])
    (make-directory* d-dir)
    (for ([f (in-list (directory-list c-dir))])
      (define ht (call-with-input-file* (build-path c-dir f) read))
      (define new-ht
        (hash-set ht 'source (relative-path->relative-url-string
                              (build-path
                               from-catalog-dir-to-pkgs-dir
                               pkgs-dir
                               (path-add-suffix f #".zip")))))
      (call-with-output-file* 
       (build-path d-dir f)
       (lambda (o)
         (write new-ht o)
         (newline o))))))

(build-catalog built-dir)
(when (directory-exists? native-dir)
  (build-catalog native-dir))
(let ([l (directory-list (build-path dest-dir catalog-dir "pkg"))])
  ;; Write list of packages:
  (define sl (map path-element->string l))
  (call-with-output-file*
   (build-path dest-dir catalog-dir "pkgs")
   (lambda (o)
     (write sl o)
     (newline o)))
  ;; Write hash table of package details:
  (define dht
    (for/hash ([f (in-list l)])
      (values (path-element->string f)
              (call-with-input-file*
               (build-path dest-dir catalog-dir "pkg" f)
               read))))
  (call-with-output-file*
   (build-path dest-dir catalog-dir "pkgs-all")
   (lambda (o)
     (write dht o)
     (newline o)))
  ;; Be friendly to people who paste the catalog URL into a web browser:
  (call-with-output-file*
   (build-path dest-dir catalog-dir "index.html")
   (lambda (o)
     (write-xexpr `(html
                    (head (title "Package Catalog"))
                    (body (p "This is a package catalog, which is not really"
                             " meant to be viewed in a browser. Package"
                             " tools read " (tt (a ([href "pkgs"]) "pkgs")) ","
                             " " (tt (a ([href "pkgs-all"]) "pkgs-all")) ", or"
                             " " (tt "pkg/" (i "package-name")) ".")))
                  o))))

(copy log-dir)
(generate-index-html dest-dir log-dir www-site)

;; If all builds failed, installers director won't exist:
(unless (file-exists? (build-path build-dir installers-dir "table.rktd"))
  (make-directory* (build-path build-dir installers-dir))
  (call-with-output-file* (build-path build-dir installers-dir "table.rktd") (lambda (o) (write (hash) o))))

(copy installers-dir)
(generate-index-html dest-dir installers-dir www-site)

(define installers-table-path
  (build-path dest-dir
              installers-dir
              "table.rktd"))
(define installers-table (get-installers-table installers-table-path))

(define logs-table-path
  (build-path dest-dir
              log-dir
              "logs-table.rktd"))

(unless (zero? (hash-count post-processes))
  (for ([(name installer) (in-hash installers-table)])
    (define post-process (hash-ref post-processes name #f))
    (when post-process
      (define args (append post-process (list (build-path dest-dir installers-dir installer))))
      (unless (apply system* args)
        (error 'post-process "failed for ~s" args)))))

(for ([(name installer) (in-hash installers-table)])
  (define main+aliases (hash-ref aliases name #f))
  (when main+aliases
    (define main (car main+aliases))
    (for ([alias (in-list (cdr main+aliases))])
      (unless (equal? alias main)
        (define alias-name (infer-installer-alias installer main alias))
        (make-file-or-directory-link installer
                                     (build-path dest-dir installers-dir alias-name))))))

(define doc-path (build-path docs-dir doc-dir))
(when (directory-exists? doc-path)
  (copy doc-dir docs-dir))
(define pdf-doc-path (build-path build-dir pdf-doc-dir))
(when (directory-exists? pdf-doc-path)
  (copy pdf-doc-dir)
  (generate-index-html dest-dir pdf-doc-dir www-site))
(copy "stamp.txt")
(copy (build-path "origin" "collects.tgz"))

(make-download-page installers-table-path
                    #:logs-table-file logs-table-path
                    #:plt-www-site www-site
                    #:title site-title
                    #:installers-url "installers/"
                    #:log-dir-url "log/"
                    #:docs-url (and (directory-exists? doc-path)
                                    "doc/index.html")
                    #:pdf-docs-url (and (directory-exists? pdf-doc-path)
                                        "pdf-doc/")
                    #:dest (build-path dest-dir
                                       "index.html")
                    #:help-table (hash-ref config '#:site-help (hash))
                    #:help-fallbacks (hash-ref config '#:site-help-fallbacks '())
                    #:git-clone (current-directory))
