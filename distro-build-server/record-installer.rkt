#lang racket/base
(require racket/file)

(provide record-installer
         record-log-file)

(define (update-table table-file filename desc)
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
                  filename))
       (call-with-output-file table-file
         #:exists 'truncate/replace
         (lambda (o) 
           (write t o)
           (newline o))))
     void)))

(define (record-installer dir filename desc)
  (update-table (build-path dir "table.rktd") filename desc))

(define (record-log-file dir log-file desc)
  (update-table (build-path dir "logs-table.rktd") log-file desc))
