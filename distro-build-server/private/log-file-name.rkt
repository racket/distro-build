#lang racket/base

(provide simplify-log-file-name)

;; simplify name to avoid characters that make an awkward file name
(define (simplify-log-file-name name)
  (let* ([name (regexp-replace* #rx"(?:{[^}]*})|[][|;*!()]" name "")]
         [name (regexp-replace #rx"^ +" name "")]
         [name (regexp-replace #rx" +$" name "")]
         [name (regexp-replace* #rx" +" name "_")])
    name))
