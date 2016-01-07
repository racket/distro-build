#lang at-exp racket/base
(require racket/system
         racket/file
         racket/format
         file/tar
         setup/cross-system)

(provide installer-tgz)

(define (system/show . l)
  (displayln (apply ~a #:separator " " l))
  (unless (apply system* (find-executable-path (car l)) (cdr l))
    (error "failed")))

(define (generate-tgz src-dir dest-path target-dir-name readme)
  (system/show "chmod" "-R" "g+w" src-dir)
  (define dest (path->complete-path dest-path))
  (when (file-exists? dest) (delete-file dest))
  (printf "Tarring to ~s\n" dest)
  (when readme
    (call-with-output-file*
     (build-path src-dir "README")
     #:exists 'truncate
     (lambda (o)
       (display readme o))))
  (parameterize ([current-directory src-dir])
    (apply tar-gzip dest #:path-prefix target-dir-name (directory-list))))

(define (installer-tgz source? base-name dir-name dist-suffix readme)
  (define tgz-path (format "bundle/~a-~a~a.tgz"
                           base-name
                           (if source?
                               "src"
                               (get-platform-name)) 
                           dist-suffix))
  (generate-tgz "bundle/racket" tgz-path
                dir-name
                readme)
  tgz-path)

(define (get-platform-name)
  (case (cross-system-type)
    [(windows)
     (define-values (base name dir?) (split-path (cross-system-library-subpath #f)))
     (format "~a-win32" (bytes->string/utf-8 (path-element->bytes name)))]
    [else
     (format "~a" (cross-system-library-subpath #f))]))
