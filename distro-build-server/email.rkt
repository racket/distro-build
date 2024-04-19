#lang racket/base
(require racket/format
         net/head
         net/smtp
         net/sendmail
         openssl
         racket/tcp)

(provide send-email)

(define (send-email to-email get-opt
                    stamp
                    start-seconds end-seconds
                    failures)
  (let ([server (get-opt '#:smtp-server #f)]
        [from-email (or (get-opt '#:email-from #f)
                        (car to-email))]
        [subject (~a "[build] "
                     (if (null? failures)
                         "success"
                         "FAILURE")
                     " " stamp)]
        [message (append
                  (if (null? failures)
                      '("All builds succeeded.")
                      (cons
                       "The following builds failed:"
                       (for/list ([i (in-list failures)])
                         (~a " " i))))
                  (list
                   ""
                   (let ([e (- end-seconds start-seconds)]
                         [~d (lambda (n)
                               (~a n #:width 2 #:pad-string "0" #:align 'right))])
                     (~a "Elapsed time: "
                         (~d (quotient e (* 60 60)))
                         ":"
                         (~d (modulo (quotient e (* 60)) 60))
                         ":"
                         (~d (modulo e (* 60 60)))))
                   ""
                   (~a "Stamp: " stamp)))])
    (cond
     [server
      (let* ([smtp-connect (get-opt '#:smtp-connect 'plain)]
             [port-no (get-opt '#:smtp-port 
                               (case smtp-connect
                                 [(plain) 25]
                                 [(ssl) 465]
                                 [(tls) 587]))])
        (define-values (user password)
          (let ([path (get-opt '#:smtp-user+password-file #f)])
            (if path
                (call-with-input-file path (lambda (i) (values (read i) (read i))))
                (values #f #f))))
        (parameterize ([smtp-sending-server (or (get-opt '#:smtp-sending-server #f)
                                                "localhost")])
          (smtp-send-message server
                             #:port-no port-no
                             #:tcp-connect (if (eq? 'ssl smtp-connect)
                                               (lambda (server port)
                                                 (ssl-connect server port 'secure))
                                               tcp-connect)
                             #:tls-encode (and (eq? 'tls smtp-connect)
                                               (lambda (i o
                                                          #:mode mode
                                                          #:encrypt encrypt ; dropped
                                                          #:close-original? close?)
                                                 (ports->ssl-ports i o
                                                                   #:mode mode
                                                                   #:close-original? close?)))
                             #:auth-user (or (get-opt '#:smtp-user #f) user)
                             #:auth-passwd (or (get-opt '#:smtp-password #f) password)
                             from-email
                             to-email
                             (standard-message-header from-email
                                                      to-email
                                                      null
                                                      null
                                                      subject)
                             message)))]
     [else
      (send-mail-message from-email
                         subject	 	 	 	 
                         to-email
                         null
                         null
                         message)])))
