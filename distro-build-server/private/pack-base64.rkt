#lang racket/base
(require net/base64)

(provide pack-base64-strings)

(define (pack-base64-strings args)
  (bytes->string/utf-8 (base64-encode (string->bytes/utf-8 (format "~s" args))
                                      #"")))
