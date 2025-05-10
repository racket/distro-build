#lang racket/base
(require racket/file)

(provide record-using-docker-container)

(define (record-using-docker-container table-file name)
  (call-with-file-lock/timeout
   #:max-delay 2
   table-file
   'exclusive
   (lambda ()
     (define names
       (if (file-exists? table-file)
           (file->lines table-file)
           null))
     (unless (member name names)
       (call-with-output-file table-file
         #:exists 'append
         (lambda (o)
           (displayln name o)))))
   void))
