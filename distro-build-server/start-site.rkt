#lang racket/base
(require racket/cmdline
         racket/string
         (only-in "config.rkt" extract-options))

(module test racket/base)

(define-values (config-file config-mode)
  (command-line
   #:args
   (config-file config-mode)
   (values config-file config-mode)))

(define config (extract-options config-file config-mode))

((hash-ref config '#:start-hook (lambda () void)))
