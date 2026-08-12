#lang racket/base
(require pkg/lib
         (prefix-in db: pkg/db)
         racket/cmdline
         racket/file
         net/url
         setup/getinfo)

;;  This module is run in a cross environment to build packages

(module test racket/base)

(define original-repo-template #f)
(define existing-catalogs null)
(define default-author "plt@racket-lang.org")
(define check-package-implies #f)

(define-values (site-dir info-cat local-packages)
  (command-line
   #:once-each
   [("--original-template") template "Set original repo using <prefix>"
                            (set! original-repo-template template)]
   [("--default-author") author "Set default author to <author>"
                         (set! default-author author)]
   [("--check-package-implies") pkg "Check that <pkg> depends on excluded packages"
                                (set! check-package-implies pkg)]
   #:multi
   [("++existing-catalog") cat "Add <cat> to list of existing"
                           (set! existing-catalogs (cons cat existing-catalogs))]
   #:args (site-dir info-cat . local-package)
   (values site-dir info-cat local-package)))

(define addon-dir (find-system-path 'addon-dir))
(define dest-dir (build-path site-dir "pkgs"))

(define tmp-catalog (build-path site-dir "pkgs.sqlite"))
(define dest-catalog (build-path site-dir "catalog"))

;; Get all package names that are from the existing catalogs; we don't want to
;; provide these
(define main-pkgs
  (for/fold ([main-pkgs (hash)]) ([main-cat (in-list existing-catalogs)])
    (printf "Main catalog: ~a\n" main-cat)
    (parameterize ([current-pkg-catalogs (list (string->url main-cat))])
      (for/fold ([main-pkgs main-pkgs]) ([(name details) (in-hash (get-all-pkg-details-from-catalogs))])
        (hash-set main-pkgs name details)))))

(define implied-packages
  (and check-package-implies
       (let loop ([pkgs (hash "racket" #t)]
                  [pkg check-package-implies])
         (cond
           [(hash-ref pkgs pkg #f) pkgs]
           [else
            (define new-pkgs (hash-set pkgs pkg #t))
            (define details (hash-ref main-pkgs pkg))
            (for/fold ([pkgs new-pkgs]) ([dep (in-list (hash-ref details 'dependencies null))])
              (loop pkgs (if (pair? dep)
                             (car dep)
                             dep)))]))))

(define pkg-details
  (parameterize ([current-pkg-catalogs (list (string->url info-cat))])
    (get-all-pkg-details-from-catalogs)))

(define installed-pkgs
  (for/hash ([pkg (in-list (installed-pkg-names #:scope 'user))])
    (values pkg #t)))

(define catalog-pkgs
  (for/fold ([ht installed-pkgs]) ([k (in-hash-keys main-pkgs)])
    (cond
      [(hash-ref ht k #f)
       (when implied-packages
         (unless (hash-ref implied-packages k #f)
           (error 'build-catalog
                  "needed package is in main catalog, but not a dependency of ~s: ~s"
                  check-package-implies
                  k)))
       (hash-remove ht k)]
      [else ht])))

(printf "Packages to catalog:\n")
(for ([k (in-hash-keys catalog-pkgs)])
  (printf "  ~a\n" k))

;; We'd like to use `pkg-archive`, but it doesn't support
;; a stripping mode (which needs to be 'built) as of v9.2. Also,
;; we want to specify an `#:original` URL to better support
;; `raco pkg update --clone`

(define cache (make-hash))

(parameterize ([db:current-pkg-catalog-file tmp-catalog])
  (db:set-catalogs! (list "local"))
  (db:set-pkgs! "local" (hash-keys catalog-pkgs)))

(make-directory* dest-dir)
(for ([name (in-hash-keys catalog-pkgs)])
  (define pkg-dir (pkg-directory name #:cache cache))
  (define info (get-info/full pkg-dir))

  (define (extract-pkg p) (if (pair? p) (car p) p))

  (define deps (map extract-pkg (info 'deps (lambda () null))))
  (define build-deps (map extract-pkg (info 'build-deps (lambda () null))))

  (define mod-paths (pkg-directory->module-paths pkg-dir name))

  (define details (hash-ref pkg-details name (hash)))

  (define local? (and (member name local-packages) #t))

  (define author
    (if (not local?)
        (hash-ref details 'author default-author)
        (let ([authors (info 'pkg-authors (lambda () (list default-author)))])
          (if (pair? authors)
              (let ([author (car authors)])
                (if (symbol? author)
                    (format "~a@racket-lang.org" author)
                    author))
              default-author))))

  (define desc
    (if (not local?)
        (hash-ref details 'description "")
        (info 'pkg-desc (lambda () ""))))

  (printf "~a by ~a: ~a\n" name author desc)

  (pkg-create 'zip
              pkg-dir
              #:dest dest-dir
              #:mode 'built
              #:original (if (not local?)
                             (hash-ref details 'source #f)
                             (and original-repo-template
                                  (format original-repo-template name))))

  (define source-file (build-path dest-dir (string-append name ".zip")))
  (define checksum (file->string (build-path dest-dir (string-append name ".zip.CHECKSUM"))))

  (parameterize ([db:current-pkg-catalog-file tmp-catalog])
    (db:set-pkg! name "local"
                 author
                 (path->string source-file)
                 checksum
                 desc)
    (db:set-pkg-dependencies! name "local"
                              checksum
                              (hash-keys
                               (for/hash ([k (in-list (append deps build-deps))])
                                 (values k #t))))
    (db:set-pkg-modules! name "local"
                         checksum
                         mod-paths))

  (pkg-catalog-copy (list tmp-catalog)
                    dest-catalog
                    #:force? #t
                    #:override? #t
                    #:relative-sources? #true))

(delete-file tmp-catalog)
