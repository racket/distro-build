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

(define create-mode 'built)

(define pkg-info-file
  (command-line
   #:once-each
   [("--mode") mode "Create package archives for <mode>"
    (set! create-mode (string->symbol mode))]
   #:args (pkg-info-file)
   pkg-info-file))

(define build-dir "build")
(define dest-dir (build-path build-dir (~a create-mode)))
(define pkg-dest-dir (path->complete-path (build-path dest-dir "pkgs")))
(define catalog-dir (build-path dest-dir "catalog"))
(define catalog-pkg-dir (build-path catalog-dir "pkg"))
(make-directory* pkg-dest-dir)
(make-directory* catalog-pkg-dir)

(define pkg-details (call-with-input-file* pkg-info-file read))

(define pkg-cache (make-hash))

(define (prefer-binary? pkg)
  (define dir (pkg-directory pkg #:cache pkg-cache))
  (define i (get-info/full dir))
  (define mode (and i (i 'distribution-preference (lambda () #f))))
  (or (eq? mode 'binary)
      (and
       ;; Any ".rkt" or ".scrbl" other than "info.rkt"?
       (not (for/or ([f (in-directory dir)])
              (and (regexp-match? #rx"[.](scrbl|rkt)$" f)
                   (not (let-values ([(base name dir?) (split-path f)])
                          (equal? #"info.rkt" (path->bytes name)))))))
       ;; Any native library?
       (for/or ([f (in-directory dir)])
         (regexp-match? #rx"[.](dll|so(|[.][-.0-9]+)|dylib|framework)$" f)))))
   
(for ([pkg (in-list (installed-pkg-names))])
  (define ht (hash-ref pkg-details pkg (hash)))
  (define dest-zip (build-path pkg-dest-dir (~a pkg ".zip")))
  (pkg-create 'zip pkg
              #:source 'name
              #:dest pkg-dest-dir
              #:mode (if (prefer-binary? pkg)
                         'binary
                         create-mode))
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
                  'description (hash-ref ht 'author "library")
                  'tags (hash-ref ht 'tags '())
                  'dependencies (hash-ref ht 'dependencies '())
                  'modules (hash-ref ht 'modules '()))
            o)
     (newline o))))
