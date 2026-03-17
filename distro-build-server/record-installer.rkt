#lang racket/base
(require racket/file
         json
         (only-in file/sha1 bytes->hex-string))

(provide record-installer
         record-log-file
         update-installers-checksums)

(define (write-json-file rktd-file table)
  (define json-file (path-replace-extension rktd-file #".json"))
  (define json-table
    (for/hash ([(k v) (in-hash table)])
      (values (string->symbol k) v)))
  (call-with-output-file json-file
    #:exists 'truncate/replace
    (lambda (o)
      (write-json json-table o)
      (newline o))))

(define (update-table table-file value desc)
  (when desc
    (call-with-file-lock/timeout
     #:max-delay 2
     table-file
     'exclusive
     (lambda ()
       (define t (hash-set
                  (if (file-exists? table-file)
                      (call-with-input-file* table-file read)
                      (hash))
                  desc
                  value))
       (call-with-output-file table-file
         #:exists 'truncate/replace
         (lambda (o)
           (write t o)
           (newline o)))
       (write-json-file table-file t))
     void)))

(define (file-checksums path)
  (if (file-exists? path)
      (hash 'sha1 (bytes->hex-string
                    (call-with-input-file* path sha1-bytes))
            'sha256 (bytes->hex-string
                     (call-with-input-file* path sha256-bytes)))
      (hash 'sha1 "" 'sha256 "")))

(define (record-installer dir filename desc)
  (update-table (build-path dir "table.rktd") filename desc)
  (define checksums (file-checksums (build-path dir filename)))
  (update-table (build-path dir "installers.rktd")
                (hash-set checksums 'filename filename)
                desc))

;; Recompute checksums for all entries in installers.rktd
;; based on the actual files in dir
(define (update-installers-checksums dir)
  (define table-file (build-path dir "installers.rktd"))
  (when (file-exists? table-file)
    (define updated
      (for/hash ([(desc entry) (in-hash (call-with-input-file* table-file read))])
        (define filename (hash-ref entry 'filename))
        (define checksums (file-checksums (build-path dir filename)))
        (values desc (hash-set checksums 'filename filename))))
    (call-with-output-file table-file
      #:exists 'truncate/replace
      (lambda (o)
        (write updated o)
        (newline o)))
    (write-json-file table-file updated)))

(define (record-log-file dir log-file desc)
  (update-table (build-path dir "logs-table.rktd") log-file desc))
