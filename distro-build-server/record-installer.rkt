#lang racket/base
(require racket/file)

(provide record-installer)

(define (record-installer dir filename desc)
  (when desc
    (define table-file (build-path dir "table.rktd"))
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
