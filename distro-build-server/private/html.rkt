#lang racket/base
(require scribble/html
         racket/match)

(provide xexpr->html)

(define (xexpr->html x)
  (match x
    [`(,(and (? symbol?) tag)
       ([,(and (? symbol?) attr) ,(and (? string?) val)]
        ...)
       ,body
       ...)
     (make-element tag (map cons attr val) (map xexpr->html body))]
    [`(,(and (? symbol?) tag)
       ,body
       ...)
     (make-element tag null (map xexpr->html body))]
    [else x]))
