#lang racket/base
(require racket/cmdline
         racket/file
         racket/path
         net/base64)

(provide set-pref-defaults)

(module test racket/base)

(module+ main
  (command-line
   #:args
   (dest-defaults-file defaults-as-base64)
   (set-pref-defaults dest-defaults-file defaults-as-base64)))

(define (set-pref-defaults dest-defaults-file
                           defaults-as-base64)
  (define new-prefs (read
                     (open-input-bytes
                      (base64-decode (string->bytes/latin-1 defaults-as-base64)))))
  (unless (and (list? new-prefs)
               (andmap (lambda (p) (and (list? p)
                                        (= 2 (length p))
                                        (symbol? (car p))))
                       new-prefs))
    (error 'set-pref-defaults "bad defaults: ~s" new-prefs))
  (define orig-prefs
    (if (file-exists? dest-defaults-file)
        (call-with-input-file* dest-defaults-file read)
        null))

  (define prefs
    (for/fold ([prefs orig-prefs]) ([p (in-list new-prefs)])
      (define a (assq (car p) prefs))
      (cons p
            (if a
                (remq a prefs)
                prefs))))

  (make-directory* (path-only dest-defaults-file))
  (call-with-output-file dest-defaults-file
    #:exists 'truncate
    (lambda (o)
      (write prefs o)
      (newline o))))
