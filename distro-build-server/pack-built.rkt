#lang racket/base
(require pkg
         pkg/lib
         racket/format
         net/url
         racket/set
         racket/file
         racket/path
         openssl/sha1
         racket/cmdline
         setup/getinfo)

(module test racket/base)

(define create-mode 'infer)

(define pkg-info-file
  (command-line
   #:once-each
   [("--mode") mode "Create package archives for <mode>; defaults to `infer`"
    (set! create-mode (string->symbol mode))]
   #:args (pkg-info-file)
   pkg-info-file))

(define build-dir "build")
(define dest-dir (build-path build-dir (~a (if (eq? create-mode 'infer)
                                               'built
                                               create-mode))))
(define pkg-dest-dir (path->complete-path (build-path dest-dir "pkgs")))
(define catalog-dir (build-path dest-dir "catalog"))
(define catalog-pkg-dir (build-path catalog-dir "pkg"))
(make-directory* pkg-dest-dir)
(make-directory* catalog-pkg-dir)

(define pkg-details (call-with-input-file* pkg-info-file read))

(define pkg-cache (make-hash))

(define pkg-table (installed-pkg-table #:scope 'user))

(define (get-original-source pkg)
  (define i (hash-ref pkg-table pkg #f))
  (define orig (and i (pkg-info-orig-pkg i)))
  (define (add-checksum-to-url str)
    (define checksum (pkg-info-checksum i))
    (cond
      [checksum
       (define u (string->url str))
       (url->string (struct-copy url u [fragment checksum]))]
      [else str]))
  (and orig
       ;; expecting only `catalog` entries, and so only Git paths will
       ;; be recorded, but accomodate other forms just in case
       (case (car orig)
         [(clone catalog) (and (= 3 (length orig))
                               (add-checksum-to-url (caddr orig)))]
         [(git) (add-checksum-to-url (cadr orig))]
         [else (cadr orig)])))

(define (infer-mode pkg)
  (define dir (pkg-directory pkg #:cache pkg-cache))
  (define i (get-info/full dir))
  (define mode (and i (i 'distribution-preference (lambda () #f))))
  (cond
    [(or (eq? mode 'source)
         (eq? mode 'built)
         (eq? mode 'binary))
     mode]
    [(and
      ;; Any ".rkt" or ".scrbl" other than "info.rkt"?
      (not (for/or ([f (in-directory dir)])
             (and (regexp-match? #rx"[.](scrbl|rkt)$" f)
                  (not (let-values ([(base name dir?) (split-path f)])
                         (equal? #"info.rkt" (path->bytes name)))))))
      ;; Any native library?
      (for/or ([f (in-directory dir)])
        (regexp-match? #rx"[.](dll|so(|[.][-.0-9]+)|dylib|framework)$" f)))
     'binary]
    [else 'built]))

(for ([pkg (in-list (installed-pkg-names))])
  (define original (get-original-source pkg))
  (define ht (hash-ref pkg-details pkg (hash)))
  (define dest-zip (build-path pkg-dest-dir (~a pkg ".zip")))
  (pkg-create 'zip pkg
              #:source 'name
              #:dest pkg-dest-dir
              #:mode (cond
                       [(eq? create-mode 'infer) (infer-mode pkg)]
                       [else create-mode])
              #:original original)
  (call-with-output-file*
   (build-path catalog-pkg-dir pkg)
   #:exists 'truncate
   (lambda (o)
     (write (hash 'source (path->string (find-relative-path
                                         (simple-form-path catalog-dir)
                                         (simple-form-path dest-zip)))
                  'checksum (call-with-input-file* dest-zip sha1)
                  'name pkg
                  'author (hash-ref ht 'author "plt@racket-lang.org")
                  'description (hash-ref ht 'description "library")
                  'tags (hash-ref ht 'tags '())
                  'dependencies (hash-ref ht 'dependencies '())
                  'modules (hash-ref ht 'modules '()))
            o)
     (newline o))))
