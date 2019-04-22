#lang racket/base
(require racket/date
         racket/format)

(provide display-time
         duration->string)

(define (display-time #:server? [server? #f])
  (define now (seconds->date (current-seconds)))
  (printf "[~a] The ~a time is now ~a\n" 
          (parameterize ([date-display-format 'iso-8601])
            (date->string now #t))
          (if server? "server" "client")
          (date->string now #t))
  (flush-output))

(define (duration->string milliseconds)
  (define secs (inexact->exact (round (/ milliseconds 1000.0))))
  (~a (~r (quotient secs (* 60 60)) #:min-width 2 #:pad-string "0")
      ":"
      (~r (quotient (remainder secs (* 60 60)) 60) #:min-width 2 #:pad-string "0")
      ":"
      (~r (remainder secs 60) #:min-width 2 #:pad-string "0")))
