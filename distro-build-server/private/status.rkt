#lang racket/base
(provide status)

(define (status fmt . args)
  (apply printf fmt args)
  (flush-output))
